{ pkgs, ... }:
{
  imports = [];
  options = {};
  config = {
    nixpkgs = {
      overlay = [
        (final: prev: { kitty-themes = pkgs.unstable.kitty-themes; } )
      ];
    };
    programs = {
      kitty = {
        enable = true;
        package = pkgs.unstable.kitty;
        theme  = "Gruvbox Material Dark Hard";
      };
    };
  };
}
