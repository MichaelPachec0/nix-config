{pkgs, ...}:
# pkgs.nixosTest was renamed to pkgs.testers.nixosTest upstream (converted
# to a hard `throw` alias, not just deprecated) on the nixpkgs revision this
# flake is pinned to.
pkgs.testers.nixosTest {
  name = "qs-greeter";

  nodes.machine = {
    pkgs,
    lib,
    ...
  }: {
    imports = [../../features/nixos/login];

    services.graphicalLogin = {
      enable = true;
      backend = "qsGreeter";
    };

    # programs.qsGreeter.package defaults to the overlay-provided
    # pkgs.qs-greeter (helpers/overlays.nix's qsGreeter overlay). This test
    # imports only features/nixos/login, not that overlay chain, so build
    # the package straight from its own directory instead of depending on
    # whether the VM's module pkgs happens to carry the flake's overlays --
    # every other package the module touches (sway, zsh, bashInteractive,
    # jq, quickshell, winePackages.fonts, gruvbox-gtk-theme, ...) is stock
    # nixpkgs and needs no overlay at all.
    programs.qsGreeter.package = pkgs.callPackage ../qs-greeter {};

    # Only the wrapper's own writeShellApplication closure carries jq; this
    # minimal test node has no desktop environment pulling it onto the
    # system PATH, but the test script itself needs it to inspect
    # sessions.json from the outside.
    environment.systemPackages = [pkgs.jq];

    users.users.tester = {
      isNormalUser = true;
      password = "testpw";
    };

    # No u2f in the VM: this test covers the module and the greetd flow,
    # not the second factor -- a VM has no YubiKey, and 2FA needs the real
    # hardware verification in Task 14. u2fAuth is the built-in NixOS PAM
    # option (nixos/modules/security/pam.nix, security.pam.services.<name>);
    # it already defaults to false here since this test never imports the
    # yubikey feature, but is forced off explicitly so this stays correct
    # even if that ever changes.
    security.pam.services.greetd.u2fAuth = lib.mkForce false;

    # greetd execs sway as a PAM session, not a login shell, so
    # environment.variables (shell-sourced) never reaches it --
    # environment.sessionVariables is the lever that does: NixOS wires it
    # into every PAM service's session stack via pam_env
    # (security.pam.services.<name>.setEnvironment, on by default), which
    # is how greetd's exec'd sway process actually picks this up.
    # WLR_RENDERER=pixman is needed because GLES2 does not work under this
    # VM's virtio-gpu without virgl -- the identical problem and fix
    # nixos/tests/sway.nix uses, for the same underlying reason.
    environment.sessionVariables.WLR_RENDERER = "pixman";

    # QEMU's own default display (-vga std, once virtualisation.graphics
    # enables one at all) leaves sway unable to acquire a working DRM
    # output inside this VM -- switch to virtio-gpu, exactly as
    # nixos/tests/sway.nix does and for the same reason.
    virtualisation.qemu.options = ["-vga" "none" "-device" "virtio-gpu-pci"];

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("test -s /run/qs-greeter/sessions.json")
    machine.succeed("jq -e 'length > 0' /run/qs-greeter/sessions.json")

    # "settings ready" is logged from Settings._recompute() once the
    # tiered merge (Nix defaults + the writable user file) settles -- it
    # says nothing about the skin by itself, skin resolution is a separate
    # binding in shell.qml that happens to settle in the same reactive
    # pass. The real evidence the skin loaded is the negative greps for
    # the skin-failure patterns further down, not this line. The sessions
    # line below fires once Sessions.qml parsed the file the wrapper wrote
    # above.
    machine.wait_until_succeeds(
        "journalctl -t qs-greeter | grep -q 'settings ready'")
    machine.wait_until_succeeds(
        "journalctl -t qs-greeter | grep -q 'sessions: '")

    # Neither fallback path was taken: greetd was available to the greeter,
    # and the configured skin actually instantiated rather than the Loader
    # erroring or Skins.resolve() falling all the way through to "fatal".
    machine.fail(
        "journalctl -t qs-greeter | grep -q 'greetd is not available'")
    machine.fail(
        "journalctl -t qs-greeter | grep -qE "
        "'skin failed to instantiate|rejected \\(not a valid|failed to load; no usable skin'"
    )

    # NOT a proof of the redaction invariant -- an absence-of-evidence check.
    # This test never sends a keystroke (see the real-login note below), so
    # the PAM conversation is never entered and "testpw" is never handed to
    # the greeter process at all; this can only ever pass, whether or not
    # log scrubbing is correct, broken, or absent. Kept because it costs
    # nothing and becomes meaningful the moment a login can be driven
    # in-VM; until then the redaction invariant is verified only by code
    # inspection and by Session.qml's own unit-level test suite.
    # machine.fail(grep -rq ...) on /var/log/qs-greeter cannot distinguish
    # "no match" from "directory missing/unreadable" -- grep exits non-zero
    # either way -- so a silently-broken log path would pass this line too.
    machine.fail("journalctl -t qs-greeter | grep -q testpw")
    machine.fail("grep -rq testpw /var/log/qs-greeter")

    # --- proof of real rendering --------------------------------------
    # Every test up to this one runs QML under QT_QPA_PLATFORM=offscreen,
    # which has no Wayland backend and never constructs anything rooted in
    # a PanelWindow -- shell.qml's login window and screens/Backdrop.qml
    # have never actually been instantiated by any test before this one.
    # "greetd came up and nothing crashed" is not proof that changed: a
    # QEMU screendump of the virtual framebuffer is, because it captures
    # whatever the VM's GPU is actually displaying, observed from outside
    # quickshell entirely. A blank or uniform frame here would mean the
    # PanelWindow/layer-shell path never painted anything, crash or not.
    machine.screenshot("login")

    def read_ppm():
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = f"{tmp}/probe.ppm"
            machine.send_monitor_command(f"screendump {path}")
            with open(path, "rb") as f:
                return f.read()

    def parse_ppm(data):
        assert data[:2] == b"P6", f"not a raw-binary PPM: {data[:16]!r}"
        idx = 2
        tokens = []
        while len(tokens) < 3:
            while data[idx] in b" \t\r\n":
                idx += 1
            start = idx
            while data[idx] not in b" \t\r\n":
                idx += 1
            tokens.append(int(data[start:idx]))
            idx += 1
        width, height, _maxval = tokens
        return width, height, data[idx:]

    def pixel(pixels, width, x, y):
        off = (y * width + x) * 3
        return tuple(pixels[off : off + 3])

    # programs.qsGreeter.backdrop defaults to kind = "color", color =
    # "#3A6EA5". screens/Backdrop.qml paints that full-screen underneath
    # everything else, on its own PanelWindow (WlrLayer.Background); the
    # XP login dialog is a fixed-size box centered on screen (Skin.qml:
    # anchors.centerIn: parent), not full-screen. So a corner pixel should
    # still show raw backdrop, and a center pixel -- inside the dialog's
    # chrome -- should not, if the whole PanelWindow/layer-shell stack
    # actually rendered. This ties the check to a value that came from
    # this test's own Nix config, through defaults.json, through
    # Settings.qml, into the compositor's real composited output, not
    # just "some pixels happen to exist".
    expected_backdrop = (0x3A, 0x6E, 0xA5)

    def close(a, b, tol=24):
        return all(abs(x - y) <= tol for x, y in zip(a, b))

    def rendered(last_chance):
        width, height, pixels = parse_ppm(read_ppm())
        corner = pixel(pixels, width, 4, 4)
        center = pixel(pixels, width, width // 2, height // 2)
        if last_chance:
            machine.log(
                f"screendump {width}x{height}: corner={corner} "
                f"center={center} expected_backdrop~{expected_backdrop}"
            )
        return close(corner, expected_backdrop) and not close(corner, center, tol=8)

    retry(rendered)
  '';
}
