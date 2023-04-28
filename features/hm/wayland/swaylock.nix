{ pkgs, config, lib, inputs, ... }:
let nw = inputs.nixpkgs-wayland.packages.${pkgs.system};
in {
  config = {
    programs.swaylock = {
      enable = false;
      package = pkgs.unstable.swaylock-effects;
      settings = 
      {
  color = "808080";
  font-size = 24;
  indicator-idle-visible = false;
  indicator-radius = 100;
  line-color = "ffffff";
  show-failed-attempts = true;
};
    };
  };
}
