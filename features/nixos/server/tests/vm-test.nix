# VM test for the boot-counted fallback path on nixpkgs-stable.
#
# gen 1: good configuration. gen 2: same but sshd disabled, so boot-health
# fails and the entry is never blessed. The driver reboots the machine (the
# real host uses boot-health-timeout for that; its logic has its own bash
# test) until the counter is spent, expects gen 1 back, and expects
# boot-fallback-alert to have written the halt file and called the stubbed
# ntfy-send with the right generations.
#
# Usage: nix build .#checks.x86_64-linux.auto-upgrade-rollback -L
{pkgs}: let
  serverDir = ../.;
  common = {
    lib,
    pkgs,
    ...
  }: {
    imports = [
      "${serverDir}/boot-counting"
      "${serverDir}/boot-health.nix"
      "${serverDir}/boot-fallback-alert.nix"
      # A minimal stand-in for ntfy.nix's option interface, not the real
      # module: ntfy.nix's config unconditionally assigns sops.secrets.*
      # (inside an mkIf, but the module system still requires that
      # attribute path to be declared wherever it is assigned, regardless
      # of the mkIf condition's value), so importing it here would also
      # require importing sops-nix, which this test does not do. Since
      # local.ntfy.enable stays false and boot-fallback-alert.nix only
      # reads local.ntfy.package/loadCredential when local.ntfy.enable is
      # true, this stand-in only needs to make `enable` resolve to false;
      # the assertion in boot-fallback-alert.nix is satisfied instead by
      # the explicit ntfySend override below.
      ({lib, ...}: {
        options.local.ntfy = {
          enable = lib.mkEnableOption "ntfy.sh alert sender (test stand-in, unused)";
          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.writeShellScriptBin "ntfy-send-unused" "exit 1";
          };
          loadCredential = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
        };
      })
    ];
    virtualisation.useBootLoader = true;
    virtualisation.useEFIBoot = true;
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    system.switch.enable = true;
    # machine-id must persist across reboots (see upstream systemd-boot test).
    environment.etc."machine-id".text = "1234567890abcdef1234567890abcdef\n";
    services.openssh.enable = true;
    local.bootHealth = {
      enable = true;
      zerotierNetwork = null;
      # Never fire inside the test; the driver drives the reboots.
      timeoutMinutes = 600;
    };
    # local.ntfy.enable stays false (the stand-in module's default);
    # boot-fallback-alert.nix's assertion accepts an explicit ntfySend
    # instead, so this test never touches sops or LoadCredential (both
    # gated on ntfy.enable in the real module).
    local.bootFallbackAlert = {
      enable = true;
      ntfySend = pkgs.writeShellScript "ntfy-stub" ''
        { echo "title=$1"; cat; } > /var/lib/auto-upgrade/last-alert
      '';
    };
  };
in
  pkgs.testers.runNixOSTest {
    name = "auto-upgrade-rollback";
    nodes = {
      machine = {nodes, ...}: {
        imports = [common];
        system.extraDependencies = [nodes.bad.system.build.toplevel];
      };
      bad = {
        imports = [common];
        services.openssh.enable = pkgs.lib.mkForce false;
      };
    };
    testScript = {nodes, ...}: let
      good = nodes.machine.system.build.toplevel;
      bad = nodes.bad.system.build.toplevel;
    in ''
      def entries():
          return machine.succeed("ls /boot/loader/entries").split()

      def current():
          return machine.succeed("readlink -f /run/current-system").strip()

      machine.start(allow_reboot=True)
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("boot-health.service")
      machine.wait_for_unit("systemd-bless-boot.service")
      assert current() == "${good}", current()
      assert not any("+" in e for e in entries()), entries()

      # Stage the bad configuration as generation 2 (boot, never switch).
      machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${bad}")
      machine.succeed("${bad}/bin/switch-to-configuration boot")
      assert any(e.endswith("+2.conf") for e in entries()), entries()

      # Try 1: gen 2 boots, health fails (no sshd), no bless.
      machine.reboot()
      machine.wait_for_unit("multi-user.target")
      assert current() == "${bad}", current()
      machine.fail("systemctl is-active boot-health.service")
      machine.fail("systemctl is-active boot-complete.target")
      assert machine.succeed("/run/current-system/systemd/lib/systemd/systemd-bless-boot status").strip() == "indeterminate"
      assert any("+1-1.conf" in e for e in entries()), entries()

      # Try 2: same, counter reaches zero.
      machine.reboot()
      machine.wait_for_unit("multi-user.target")
      assert current() == "${bad}", current()
      machine.fail("systemctl is-active boot-complete.target")
      assert any("+0-2.conf" in e for e in entries()), entries()

      # Fallback: sd-boot skips the bad entry, gen 1 boots, alert fires.
      machine.reboot()
      machine.wait_for_unit("multi-user.target")
      assert current() == "${good}", current()
      machine.wait_for_unit("boot-fallback-alert.service")
      halted = machine.succeed("cat /var/lib/auto-upgrade/halted").strip()
      assert halted == "2", halted
      alert = machine.succeed("cat /var/lib/auto-upgrade/last-alert")
      assert "boot fallback to generation 1" in alert, alert
      assert "bad generation(s): 2" in alert, alert
      assert "rm /var/lib/auto-upgrade/halted" in alert, alert

      # A further boot of gen 1 does not re-alert.
      machine.succeed("rm /var/lib/auto-upgrade/last-alert")
      machine.reboot()
      machine.wait_for_unit("boot-fallback-alert.service")
      machine.fail("test -e /var/lib/auto-upgrade/last-alert")
    '';
  }
