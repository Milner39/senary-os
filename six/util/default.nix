{ lib
, pkgs  ? throw "six.util was called without the `pkgs` argument"
, ...
}:

let
  chpst = pkgs.callPackage ./chpst {};
  depot = pkgs.callPackage ./depot { inherit lib; };
in {
  inherit chpst;
  inherit depot;
}
