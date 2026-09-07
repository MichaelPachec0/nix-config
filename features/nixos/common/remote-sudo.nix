# sudo over a forwarded ssh-agent, so the YubiKey stays on the origin host.
#
# pam_u2f talks CTAP-HID to a local /dev/hidraw and cannot reach a key on
# another machine. pam_rssh instead asks whatever agent sits behind
# $SSH_AUTH_SOCK to sign a challenge; with `ssh -A` that socket chains back
# through every hop to the origin's ssh-agent and its sk-ssh-ed25519 key, so
# `sudo` on any hop cues one touch on the origin. The pam module keeps
# SSH_AUTH_SOCK through sudo's env_keep by itself.
#
# Trust root per host: /etc/ssh/authorized_keys.d/<user>, the root-owned file
# the sshd module already generates from `openssh.authorizedKeys.keys` and
# the path pam_rssh reads by default. Keys that can log in as a user can sudo
# as that user. pam_unix stays behind rssh in the stack, so a missing key
# falls through to the password.
#
# Every hop also needs ForwardAgent for the next hop; the system ssh_config
# here covers users without a home-manager ssh config (sysadmin on servers).
# Home-manager's ~/.ssh/config wins where it exists, with the same values.
{lib, ...}: let
  # Hosts that take part in the hop chain. zerotier addresses where the host
  # has one, public addresses otherwise.
  hops = {
    kore = {
      hostName = "172.30.0.5";
      user = "sysadmin";
    };
    atlas = {
      hostName = "142.171.216.47";
      user = "sysadmin";
    };
    selene = {
      # hostName = "152.70.124.65";
      hostName = "172.30.0.21";
      user = "sysadmin";
    };
    nyx = {
      hostName = "172.30.0.7";
      user = "michael";
    };
    thanatos = {
      hostName = "172.30.0.23";
      user = "michael";
    };
  };
in {
  security.pam = {
    rssh = {
      enable = true;
      # Print "Please touch the device" style prompts so a signature request
      # is never silent.
      settings.cue = true;
    };
    services.sudo.rssh = true;
  };

  # Other modules append un-headed lines to extraConfig (libvirt's Include,
  # for one). Without a terminator they would attach to the last Host block
  # above, so close the scope back to global.
  programs.ssh.extraConfig =
    lib.concatStrings (lib.mapAttrsToList (alias: h: ''
        Host ${alias}
          HostName ${h.hostName}
          User ${h.user}
          ForwardAgent yes
      '')
      hops)
    + ''
      Host *
    '';
}
