{ lib
, execline
, pkgs
, toPrettyTry
, ...
}:


let
  inherit (pkgs) busybox;

  inherit (lib) all isList isInt isFloat isString isDerivation isPath;

  isExeclineLeaf =
    arg:
    arg == [] ||
    isPath arg ||
    isString arg ||
    isDerivation arg;

  # returns true iff the argument consists of only lists and strings
  isExecline =
    arg:
    isExeclineLeaf arg ||
    (isList arg && all isExecline arg);

  # equivalent to `x: assert isExecline x; true` with better diagnostics
  assertIsExecline =
    arg:
    if isExeclineLeaf arg
    then true
    else let
      pretty = toPrettyTry { multiline = false; } arg;
      message = "assertIsExecline: found ${builtins.typeOf arg}, expected list or string: ${pretty}";
    in assert !(isList arg) -> throw message;
      all assertIsExecline arg;

  # Takes an execline script (list-of-strings) and returns an execline scripts
  # which executes the argument every `interval-seconds` seconds.  Important
  # FIXME: make sure that sending SIGTERM to this PID will always cause the loop to exit.
  loop =
    { interval-seconds      # may be a float (i.e. `0.1`)
    , sleep-first ? false   # sleep before the first execution
    }:
    argv:
    assert (x: isFloat x || isInt x) interval-seconds;
    assert assertIsExecline execline;
    [
      "${execline}/bin/loopwhilex"
      "${execline}/bin/if"
      argv
      "${busybox}/bin/busybox" "sleep" "${toString interval-seconds}"
    ];

in {
  inherit isExecline assertIsExecline loop;
}

