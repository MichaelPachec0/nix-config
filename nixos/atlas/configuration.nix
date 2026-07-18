# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  keys = import ../../helpers/keys.nix;
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../features/nixos/common
    ../../features/nixos/common/deploy.nix
    # ../../features/nixos/server
    ../../features/nixos/server/base.nix
    ../../helpers/caches.nix
  ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub= {
    enable = true;
    devices = [
      "/dev/vda"
    ];
  };
  boot.initrd = {
    # availableKernelModules = ["cryptd"];
    # kernelModules = ["igb"];
    #preLVMCommands = lib.mkOrder 400 "sleep 1";
    # TODO: (high prio) (research) check if it is possible to work into zerotier into initrd.
    # NOTE: 26.05 makes systemd stage-1 the initrd default
    # (boot.initrd.systemd.enable defaults to true). The scripted-only options
    # `network.flushBeforeStage2` and `network.udhcpc.enable` are unsupported
    # under systemd stage-1 and trip an assertion; DHCP for the initrd is now
    # handled by systemd-networkd via `systemd.network` below.
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = keys.initrd;
        # NOTE: MAKE SURE THESE FILES EXIST ON SYSTEM ELSE NO BOOT IS POSSIBLE
        # TODO: (high prio) (research) Include host keys here. Prereq for this will be 'sops-nix'.
        hostKeys = [
          # NOTE: on charon
          "/etc/secrets/initrd/ssh_host_rsa_key"
          # NOTE: yubi based key
          "/etc/secrets/initrd/ssh_host_ed25519_key"
        ];
      };
    };
    # systemd stage-1 networking: bring the VM NIC up via DHCP so the initrd
    # SSH remote-unlock (port 2222) is reachable, replacing the old scripted
    # udhcpc. Match Type=ether so it stays correct regardless of NIC name.
    systemd.network = {
      enable = true;
      networks."10-uplink" = {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
      };
    };
  };
  hardware.ksm.enable = true;
  machine.vm.enable = true;
  devMachine.enable = false;
  audio.enable = false;

  networking = {
    hostName = "atlas";
    # networkmanager = {enable = true;};
    firewall = {
      enable = true;
      allowedTCPPorts = [
        # iscsi
        # 3260
        # k3s
        # 10250
      ];
      allowedUDPPorts = [
      ];
    };
  };
  users.users.sysadmin = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [keys.m718 keys.m828 keys.m799 keys.m791];
  };


  environment.systemPackages = with pkgs; [
    neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
  ];

  # environment.persistence."/persist" = {
  #   enable = true; # NB: Defaults to true, not needed
  #   hideMounts = true;
  #   directories = [
  #     "/var/log"
  #     "/var/lib/bluetooth"
  #     "/var/lib/nixos"
  #     "/var/lib/systemd/coredump"
  #     "/etc/NetworkManager/system-connections"
  #     "/etc/secrets/initrd"
  #     "/etc/ssh"
  #     {
  #       directory = "/var/lib/colord";
  #       user = "colord";
  #       group = "colord";
  #       mode = "u=rwx,g=rx,o=";
  #     }
  #   ];
  #   files = [
  #     "/etc/machine-id"
  #     {
  #       file = "/var/keys/secret_file";
  #       parentDirectory = {mode = "u=rwx,g=,o=";};
  #     }
  #   ];
  #   users.sysadmin = {
  #     directories = [
  #       "Downloads"
  #       "Music"
  #       "Pictures"
  #       "Documents"
  #       "Videos"
  #       "VirtualBox VMs"
  #       {
  #         directory = ".gnupg";
  #         mode = "0700";
  #       }
  #       {
  #         directory = ".ssh";
  #         mode = "0700";
  #       }
  #       {
  #         directory = ".nixops";
  #         mode = "0700";
  #       }
  #       {
  #         directory = ".local/share/keyrings";
  #         mode = "0700";
  #       }
  #       ".local/share/direnv"
  #     ];
  #     files = [
  #       ".screenrc"
  #     ];
  #   };
  # };

  # Open ports in the firewall.

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
}
