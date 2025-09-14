{
  prev,
  pkgs,
  lib,
  isHyprland ? false,
}: (old: let
  date = "7-29-2023";
  cava = prev.fetchFromGitHub {
    owner = "LukashonakV";
    repo = "cava";
    rev = "0.8.5";
    sha256 = "b/XfqLh8PnW018sGVKRRlFvBpo2Ru1R2lUeTR7pugBo=";
  };
  rev = "94c34a29c4e377bd9b2ab08e07a034336ed93e27";
  sha256 = "IPxXzQ9ski5Clai0uURgLgrD4JFB4d7IwVCqjU62yQY=";
  shortRev = builtins.substring 0 7 "${rev}";
  pversion = "0.9.20-pre";
in {
  pname =
    if isHyprland
    then "${old.pname}-hyprland"
    else old.pname;
  withMediaPlayer = true;

  version = "${pversion}+date=${date}_${shortRev}";

  nativeBuildInputs =
    (old.nativeBuildInputs or [])
    ++ (with pkgs; [cmake]);

  propagatedBuildInputs =
    (old.propagatedBuildInputs or [])
    ++ (with pkgs; [
      iniparser
      fftw
      ncurses
      alsa-lib
      libpulseaudio
      portaudio
      pipewire
      SDL2
    ]);
  src = prev.fetchFromGitHub {
    inherit rev sha256;
    owner = "Alexays";
    repo = "Waybar";
  };
  mesonFlags =
    (old.mesonFlags or [])
    ++ (lib.optionals isHyprland ["-Dexperimental=true"]);
  postUnpack = ''
    rm -rf source/subprojects/cava.wrap
    ln -s ${cava} source/subprojects/cava
  '';
})
