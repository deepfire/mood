{ mkDerivation, aeson, base, base-unicode-symbols, binary
, bytestring, cairo, clock, containers, dependent-sum, directory
, dlist, exceptions, extra, filepath, free, freer-simple, fsnotify, ghc-prim
, gi-cairo, gi-pango, gi-pangocairo, GLFW-b, Glob, hashable
, haskell-gi-base, hedgehog, hspec, hxt, JuicyPixels
, lambdacube-compiler, lambdacube-gl, lambdacube-ir
, lambdacube-quake3, lens, linear, lub, metamorphic, MissingH
, monadplus, MonadRandom, mono-traversable, mtl, OpenGL, OpenGLRaw
, parsers, pretty, pretty-show, primitive, profunctors, proteaaudio
, QuickCheck, random, ref-tf, reflex, semigroupoids
, semigroups, singletons, stdenv, stm, tasty, tasty-discover
, tasty-expected-failure, tasty-hedgehog, tasty-hspec, tasty-hunit
, tasty-quickcheck, tasty-smallcheck, template-haskell, text
, text-format, text-lens, text-zipper, these, transformers
, trifecta, unordered-containers, vect, vector, wl-pprint-extras
, wl-pprint-text
}:
mkDerivation {
  pname = "holotype";
  version = "0.0.1";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    aeson base base-unicode-symbols binary bytestring cairo clock
    containers dependent-sum directory dlist exceptions extra filepath
    free freer-simple fsnotify ghc-prim gi-cairo gi-pango gi-pangocairo GLFW-b
    hashable haskell-gi-base hedgehog hspec hxt JuicyPixels
    lambdacube-compiler lambdacube-gl lambdacube-ir lambdacube-quake3
    lens linear lub metamorphic MissingH monadplus MonadRandom
    mono-traversable mtl OpenGL OpenGLRaw parsers pretty pretty-show
    primitive profunctors proteaaudio QuickCheck random ref-tf
    reflex semigroupoids semigroups singletons stm tasty
    tasty-expected-failure tasty-hedgehog tasty-hspec tasty-hunit
    tasty-quickcheck tasty-smallcheck template-haskell text text-format
    text-lens text-zipper these transformers trifecta
    unordered-containers vect vector wl-pprint-extras wl-pprint-text
  ];
  executableHaskellDepends = [
    aeson base base-unicode-symbols bytestring cairo clock containers
    directory free gi-cairo gi-pangocairo GLFW-b haskell-gi-base
    lambdacube-compiler lambdacube-gl lambdacube-ir lambdacube-quake3
    lens linear mtl OpenGLRaw pretty-show text text-zipper vector
  ];
  testHaskellDepends = [
    base base-unicode-symbols containers directory filepath Glob
    hedgehog lens linear tasty tasty-discover tasty-expected-failure
    tasty-hedgehog tasty-hspec tasty-hunit tasty-quickcheck
    tasty-smallcheck
  ];
  description = "Graph-backed visual mind assistant";
  license = stdenv.lib.licenses.agpl3;
}
