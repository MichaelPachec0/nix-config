# Reproducer for a compositor that strands a client-allocated new_id in
# ext_session_lock_v1.get_lock_surface. See ./README.md.
#
# Depends only on wayland + wayland-protocols, so it runs against any
# compositor, not just the one it was written for.
{
  lib,
  stdenv,
  pkg-config,
  wayland,
  wayland-scanner,
  wayland-protocols,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "hypr-lock-strand-repro";
  version = "1.0.0";

  # Only what the build reads: keeps README/flake edits from forcing a rebuild.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./strand.c
    ];
  };

  strictDeps = true;
  nativeBuildInputs = [pkg-config wayland-scanner];
  buildInputs = [wayland];

  # Bindings generated at build time from wayland-protocols, not vendored, so
  # the tool tracks whatever version nixpkgs carries.
  protocolXml = "${wayland-protocols}/share/wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml";

  buildPhase = ''
    runHook preBuild

    test -f "$protocolXml" || {
      echo "ext-session-lock-v1.xml not found at $protocolXml" >&2
      exit 1
    }

    wayland-scanner private-code  "$protocolXml" ext-session-lock-v1-protocol.c
    wayland-scanner client-header "$protocolXml" ext-session-lock-v1-client-protocol.h

    # -Werror on purpose: a warning means the bindings changed shape under us.
    $CC -o hypr-lock-strand-repro \
      strand.c ext-session-lock-v1-protocol.c \
      -Wall -Wextra -Werror -O2 \
      $(pkg-config --cflags --libs wayland-client)

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 hypr-lock-strand-repro $out/bin/hypr-lock-strand-repro
    runHook postInstall
  '';

  # Cheap ELF sanity check; the real check needs a live compositor.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/hypr-lock-strand-repro --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Detect a Wayland compositor that strands a client-allocated ext_session_lock_surface_v1 id";
    longDescription = ''
      ext_session_lock_v1.get_lock_surface carries a new_id, which in Wayland is
      allocated by the client and never acknowledged. A compositor that returns
      from the handler without constructing an object leaves the client holding
      a proxy for an id the compositor has never heard of, and the client is
      killed with wl_display.error(0, "invalid object N") on its next request to
      that proxy, which is usually destroy.

      This tool drives that path on purpose and reports SURVIVED or KILLED. It
      locks and unlocks the session before issuing the request under test, so a
      kill cannot strand the session.

      Affects Hyprland through at least v0.56.2. wlroots-based compositors,
      including sway, are unaffected: wlroots creates the object before
      validating anything and leaves it inert.
    '';
    homepage = "https://github.com/hyprwm/Hyprland";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.linux;
    mainProgram = "hypr-lock-strand-repro";
  };
})
