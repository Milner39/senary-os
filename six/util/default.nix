{ lib
, pkgs
}:

let
  chpst = pkgs.callPackage ./chpst {};
  depot = pkgs.callPackage ./depot { inherit lib; };
in {
  inherit chpst;
  inherit depot;
}
