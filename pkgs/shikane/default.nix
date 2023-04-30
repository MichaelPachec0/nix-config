{ lib, fetchCrate, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "shikane";
  version = "0.2.0";

  src = fetchCrate {
    inherit pname version;
    sha256 = "sha256-yLrUl3o4JT8D4yyTDr2FWR21UxXaMcPH7W5to1ar6ac=";
  };
  cargoHash = "sha256-4wisXVaZa2GBFKywl48beQgg4c+lawL3L/837ZU1Y94=";

  meta = with lib; {
    description =
      "A dynamic output configuration tool that automatically detects and configures connected outputs based on a set of profiles.";
    homepage = "https://gitlab.com/w0lff/shikane";
    license = licenses.mit;
    maintainers = with maintainers; [ MichaelPachec0 ];
  };
}
