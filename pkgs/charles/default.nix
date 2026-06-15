# NOTE: this does not work with the current version of charles that is being pulled by nixpkgs
_final: prev: {
  charles = prev.charles.overrideAttrs (old: {
    inherit (old) pname src;
    version = "${old.version}-bad";
    preConfigurePhases = (old.preConfigurePhases or []) ++ ["badPatch"];
    badPatch = ''
      JAR=$TMPDIR/charles/lib/charles.jar
      CLASS=C0143p
      JFILE=''${TMPDIR}/''${CLASS}.java

      cat >>$JFILE<<EOF
      package com.xk72.charles;
      public final class ''${CLASS}{
      public static boolean ad() { return true; }
      public static boolean a() { return true; }
      public static String ac() { return "Administrator"; }
      public static String ae() { return "Administrator"; }
      public static String a(String name, String key) { return null; }
      }
      EOF
      ${prev.jdk11}/bin/javac -encoding UTF-8 $JFILE -d $TMPDIR
      ${prev.jdk11}/bin/jar -uvf $JAR $TMPDIR/com/xk72/charles/$CLASS.class
    '';
  });
}
