# Patched lldb for Rust language support.
{ fetchFromGitHub, runCommand, llvmPackages, python3 }:
let
  llvmSrc = fetchFromGitHub {
    owner = "vadimcn";
    repo = "llvm-project";
    # codelldb/14.x branch
    rev = "4c267c83cbb55fedf2e0b89644dc1db320fdfde7";
    sha256 = "sha256-jM//ej6AxnRYj+8BAn4QrxHPT6HiDzK5RqHPSg3dCcw=";
  };
in (llvmPackages.lldb.overrideAttrs (oldAttrs: rec {
  version = "${oldAttrs.version}-patched";
  passthru = (oldAttrs.passthru or {}) // {
    inherit llvmSrc;
  };

  patches = oldAttrs.patches ++ [
    # backport of https://github.com/NixOS/nixpkgs/commit/0d3002334850a819d1a5c8283c39f114af907cd4
    # remove when https://github.com/NixOS/nixpkgs/issues/166604 fixed
    ./fix-python-installation.patch
  ];

  doInstallCheck = true;
  # Extremely hacky way to deal with the bad symlink on the file
  postInstall = ''
  rm $lib/${python3.sitePackages}/lldb/lldb-argdumper
  # get a cyclic symlink error, instead just do a copy
  cp $out/bin/lldb-argdumper $lib/${python3.sitePackages}/lldb/
  '';

  # installCheck for lldb_14 currently broken
  # https://github.com/NixOS/nixpkgs/issues/166604#issuecomment-1086103692
  # ignore the oldAttrs installCheck
  installCheckPhase = ''
    versionOutput="$($out/bin/lldb --version)"
    echo "'lldb --version' returns: $versionOutput"
    echo "$versionOutput" | grep -q 'rust-enabled'
  '';
})).override({
  monorepoSrc = llvmSrc;
  libllvm = llvmPackages.libllvm.override({ monorepoSrc = llvmSrc; });
})
