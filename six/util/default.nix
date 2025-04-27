{ lib
, pkgs  ? throw "six.util was called without the `pkgs` argument"
, ...
}:

let
  chpst = pkgs.callPackage ./chpst {};
  depot = pkgs.callPackage ./depot { inherit lib; };
  scriptify = pkgs.callPackage ./scriptify {
    inherit lib;
    inherit chpst;
    inherit (depot) writeExecline;
  };
  execline = pkgs.callPackage ./execline {
    inherit lib toPrettyTry;
  };

  # The following is copy-pasted from infuse.nix, which uses this routine but
  # does not expose it (since doing so would make it part of the infuse API).
  #
  # This is a `throw`-tolerant version of toPretty, so that error diagnostics in
  # this file will print "<<throw>>" rather than triggering a cascading error.
  #
  toPrettyTryWrapper = old-toPretty:
    args: val:
    let
      try = builtins.tryEval (old-toPretty args val);
    in
      if try.success
      then try.value
      else "<<throw>>";

  toPrettyTry = toPrettyTryWrapper lib.generators.toPretty;

in {
  inherit
    chpst
    depot
    scriptify
    execline
    toPrettyTryWrapper
    toPrettyTry
  ;
}
