# {
#   lib,
#   stdenv,
#   libsecret,
#   fetchFromGitHub,
# }: let
#   pname = "electron-mail";
#   version = "5.2.2";
#   name = "ElectronMail-${version}";
#
#   src = fetchFromGitHub {
#     owner = "vladimiry";
#     repo = "electronmail";
#     rev = "1fc8e256819e546c66448e3fd6f6859fb468cf17";
#     hash = "sha256-bGqTPP+djpr+RFS6X7jUlSbxl7UDUaZLWQ3D/R76zEI=";
#   };
# in
#   # TODO: do i use mkDerivation or npmBuildPackage.
#   stdenv.mkDerivation {
#     inherit name src;
# extraInstallCommands = ''
#   mv $out/bin/${name} $out/bin/${pname}
#   install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
#   substituteInPlace $out/share/applications/${pname}.desktop \
#     --replace 'Exec=AppRun' 'Exec=${pname} --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations'
#   cp -r ${appimageContents}/usr/share/icons $out/share
# '';
#   extraPkgs = pkgs: with pkgs; [libsecret libappindicator-gtk3];
#
#   meta = with lib; {
#     description = "ElectronMail is an Electron-based unofficial desktop client for ProtonMail";
#     homepage = "https://github.com/vladimiry/ElectronMail";
#     license = licenses.gpl3;
#     maintainers = [maintainers.princemachiavelli];
#     platforms = ["x86_64-linux"];
#   };
# }
{
  appimageTools,
  lib,
  fetchurl,
  makeWrapper,
  libsecret,
}: let
  pname = "electron-mail";
  # version = "5.2.3";
  version = "5.3.3";
  name = "ElectronMail-${version}";

  src = fetchurl {
    url = "https://github.com/vladimiry/ElectronMail/releases/download/v${version}/electron-mail-${version}-linux-x86_64.AppImage";
    # sha256 = "sha256-bGqTPP+djpr+RFS6X7jUlSbxl7UDUaZLWQ3D/R76zEI=";
    # sha256 = "sha256-ajekPPRgprYNWE2osAXe46qVjnxXzkXa+MkWiNYJ5Fc=";
    sha256 = "sha256-i1oJ/DNGspE7ELuN7MI0e8/69SZwirqahBa7Jf5kP7s=";

  };

  appimageContents = appimageTools.extract {inherit pname version src;};
in
  appimageTools.wrapType2 {
    inherit pname version src;

    # TODO: make this use the nixos_wl
    extraInstallCommands = ''
      # this is not needed anymore
      # mv $out/bin/${name} $out/bin/${pname}
      source "${makeWrapper}/nix-support/setup-hook"
      wrapProgram $out/bin/${pname}\
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"
      install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=${pname}'
      cp -r ${appimageContents}/usr/share/icons $out/share
    '';

    extraPkgs = pkgs:
      with pkgs; [
        libsecret
        libappindicator-gtk3
      ];

    meta = with lib; {
      description = "ElectronMail is an Electron-based unofficial desktop client for ProtonMail";
      mainProgram = "electron-mail";
      homepage = "https://github.com/vladimiry/ElectronMail";
      license = licenses.gpl3;
      maintainers = [maintainers.princemachiavelli];
      platforms = ["x86_64-linux"];
    };
  }
