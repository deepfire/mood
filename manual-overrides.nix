{ self, super, pkgs, lib, local ? false }:

with pkgs.haskell.lib; with lib; with self; {

  # lambdacube-ir     = debugBuild super.lambdacube-ir;
  # reflex            = debugBuild super.reflex;
  # cairo             = debugBuild super.cairo;
  # gi-cairo          = debugBuild super.gi-cairo;
  # gi-pango          = debugBuild super.gi-pango;
  # gi-pangocairo     = debugBuild super.gi-pangocairo;
  # GLFW-b            = debugBuild super.GLFW-b;
  # GLURaw            = debugBuild super.GLURaw;
  # OpenGL            = debugBuild super.OpenGL;
  # OpenGLRaw         = debugBuild super.OpenGLRaw;
  # proteaaudio       = debugBuild super.proteaaudio;

  reflex-glfw =
  mkDerivation {
    pname = "reflex-glfw";
    version = "0.1.0";
    src = pkgs.fetchgit (removeAttrs (builtins.fromJSON (builtins.readFile ./reflex-glfw.src.json)) ["date"]);
    isLibrary = true;
    isExecutable = true;
    libraryHaskellDepends = [
      base base-unicode-symbols containers dependent-sum GLFW-b lens mtl
      OpenGLRaw pretty primitive ref-tf reflex stm transformers
    ];
    executableHaskellDepends = [
      base base-unicode-symbols containers dependent-sum GLFW-b lens mtl
      OpenGL OpenGLRaw pretty reflex stm transformers
    ];
    homepage = "https://github.com/deepfire/reflex-glfw/";
    description = "A GLFW-b adapter for Reflex FRP";
    license = stdenv.lib.licenses.bsd3;
  };
}
