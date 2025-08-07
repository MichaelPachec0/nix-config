{
  lib,
  fetchFromGitHub,
  rustPlatform,
  ...
}:
rustPlatform.buildRustPackage rec {
  pname = "fermyon-spin";
  version = "v1.5.1";
  src = fetchFromGitHub {
    owner = "fermyon";
    repo = "spin";
    rev = version;
    hash = "sha256-SCmOewEg48dOpJ7tdxFUiOQ0XMQy64cjVLozVsGQ6DQ=";
  };
  # NOTE: understand why this works. should need to specify a cargoHash no?
  # cargoHash = lib.fakeHash;
  meta = with lib; {
    description = "Spin is the open source developer tool for building and running serverless applications powered by WebAssembly.";
    homepage = "https://github.com/fermyon/spin/tree/v1.5.1";
    license = license.apache;
    maintainers = [];
  };
}
