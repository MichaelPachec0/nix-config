{ pkgs, ... }: {
  imports = [ ];
  options = { };
  config = {
    nixpkgs = {
      overlays =
        [ (final: prev: { kitty-themes = pkgs.unstable.kitty-themes; }) ];
    };
    programs = {
      kitty = {
        enable = true;
        package = pkgs.unstable.kitty;
        theme = "Gruvbox Material Dark Hard";
      };
    };
  };
}
