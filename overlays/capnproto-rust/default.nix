{
  lib,
  rustPlatform,
  ...
}: let
  src = lib.fetchFromGitHub {
    owner = "capnproto";
    repo = "capnproto-rust";
    rev = "dd9c072ce48c8e5377b3844ecaca832749eece08";
    hash = "sha256-2rvPt7y4FBsjsVHEkOOWVkfGdOGOInLc31qc8zDYZYI=";
  };
in
  rustPlatform.buildRustPackage rec {
    pname = "capnproto-rust";
    version = "0.0";
    inherit src;
    cargBuildFlags = [
      "--path ${src}/capnpc"
      "--lib"
      "--bin=capnproto-rust"
    ];
    meta = with lib; {
      description = "Cap'n Proto code generation";
      homepage = "https://github.com/capnproto/capnproto-rust";
      license = licenses.mit;
      maintainers = [];
    };
  }
