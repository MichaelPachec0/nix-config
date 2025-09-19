{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "languagetool-rust";
  version = "2.1.2";
  src = fetchFromGitHub {
    owner = "jeertmans";
    repo = pname;
    rev = version;
    hash = lib.fakeHash;
  };
  cargoHash = lib.fakeHash;
  meta = with lib; {
    description = "Rust bindings to connect with LanguageTool server API";
    homepage = "https://github.com/jeertmans/languagetool-rust";
    license = license.mit;
    maintainers = [maintainers.michaelpachec0];
  };
}
