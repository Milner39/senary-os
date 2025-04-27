{ lib
, system
, execline
, s6-portable-utils
, writeScript
, ...
}:

let

  getBins =
    import ./getBins {
      inherit lib;
      pkgs = throw "getBins should not need pkgs";
      depot = throw "getBins should not need depot";
    };

  escapeExecline =
    import ./escapeExecline {
      inherit lib;
    };

  runExecline =
    let
      functor =
        import ./runExecline {
          inherit lib;
          stdenv = { inherit system; };
          depot.nix = {
            inherit getBins;
            inherit escapeExecline;
          };
          pkgs = {
            inherit lib execline s6-portable-utils;
          };
        };
    in
      functor.__functor functor.__functor;

  writeExecline =
    import ./writeExecline {
      pkgs = { inherit execline; };
      depot.nix = {
        inherit escapeExecline;
        inherit writeScript;
      };
    };

in {
  inherit escapeExecline runExecline writeExecline;

}
