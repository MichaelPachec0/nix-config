# features/nixos/auth/pam/quickshell-lock.nix
# PAM service the Quickshell lock authenticates against. auth-only, includes the
# system 'login' stack (same shape as hyprlock/swaylock). Shared by all hosts
# that import features/nixos/auth.
{ ... }:
{
  security.pam.services.quickshell-lock = {
    text = ''
      auth include login
    '';
  };
}
