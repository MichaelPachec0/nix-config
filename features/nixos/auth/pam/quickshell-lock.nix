# features/nixos/auth/pam/quickshell-lock.nix
# PAM service the Quickshell lock authenticates against. Single-factor unlock:
# YubiKey OR fingerprint OR password, each `sufficient` (same shape as
# swaylock). It must NOT `include login`: the login stack is now 2FA (password
# required + a second factor), which would force two factors just to unlock the
# screen. Shared by all hosts that import features/nixos/auth.
{ ... }:
{
  security.pam.services.quickshell-lock = {
    u2fAuth = true;
    use2Factor = false;
  };
}
