#
# This contains utilities which depend on a pkgs set (i.e. instantiated nixpkgs
# beyond just nixpkgs/lib)
#
{ lib,
  sixos,
  ...
}:

{
  pkgs  ? throw "six.util was called without the `pkgs` argument"
}:

let
  chpst = pkgs.callPackage ./chpst { inherit util; };
  depot = pkgs.callPackage ./depot { inherit lib; };
  execline = pkgs.callPackage ./execline {
    inherit lib;
    inherit (sixos.lib) toPrettyTry;
  };

  network = pkgs.callPackage ./network {
    inherit lib;
  };

  util = {
    inherit
      chpst
      depot
      execline
    ;
  };

in util
