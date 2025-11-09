{ lib
, pkgs
, six

, type          ? throw "missing type"
#, description
#, documentation  # must be urls
, up            ? null # must contain a single unix command line (no shebang)
, timeout-up    ? null
, down          ? null # must contain a single unix command line (no shebang)
, timeout-down  ? null
, passthru      ? {}
, extraCommands ? ""

# Not yet implemented:
# When starting this service, start the wanted services concurrently.  No effect
# on stopping.
#, wants
#, wantedBy?
}:
assert up!=null   -> six.util.execline.assertIsExecline up;
assert down!=null -> six.util.execline.assertIsExecline down;

# TODO: prefix all runscripts with `s6-cd /run/booted-system/six/scandir/$1`?
# That way relative path references to ./data will use a path which gets updated
# by configuration activations.

let
  afterDirName = if type == "bundle" then "contents.d" else "dependencies.d";

  # applies escapeExecline if the argument is a list; this is simply to avoid
  # "diff noise" in the existing westernsemico-internal test suite
  maybeEscapeExecline =
    argv:
    assert six.util.execline.assertIsExecline argv;
    if lib.isList argv
    then six.util.depot.escapeExecline argv
    else argv;

in
(pkgs.stdenvNoCC.mkDerivation {
  name = throw "this will be overridden";
  passAsFile = [ "buildCommand" ];
  preferLocalBuild = true;
  allowSubstitutes = false;
  passthru = {
    spath = throw "service references must be via final -- i.e. `final.targets.my-service-name`, not `my-service-name`";
    after = [];
    before = [];
  } // passthru // {
    stype = type;   # apparently `type` is used internally by mkDerivation?
  };
})
.overrideAttrs(finalAttrs: previousAttrs:
  #assert type!="longrun" -> finalAttrs.passthru.logger != null -> throw "targets of type ${type} cannot have loggers";
 {
  name = "six-service-${lib.concatStringsSep "." finalAttrs.passthru.spath}";
  buildCommand = ''
    mkdir $out
    echo ${type} > $out/type
  '' + lib.optionalString (up != null) ''
    echo ${lib.escapeShellArg (maybeEscapeExecline up)} > $out/up
  '' + lib.optionalString (down != null) ''
    echo ${lib.escapeShellArg (maybeEscapeExecline down)} > $out/down
  '' + lib.optionalString (finalAttrs.passthru.essential or false) ''
    touch $out/flag-essential
  '' + lib.optionalString (timeout-up != null) ''
    echo ${timeout-up} > $out/timeout-up
  '' + lib.optionalString (timeout-down != null) ''
    echo ${timeout-down} > $out/timeout-down
  '' + ''
    mkdir $out/${afterDirName}
  '' +
  (lib.concatMapStrings (c:
    # FIXME this isn't quite right -- I guess this gets at the difference
    # between the *contents* of a bundle and the *dependencies* of an
    # atomic.  Not sure what to do here really.
    ''
    touch $out/${afterDirName}/${c}
    '')
    (
      (builtins.sort (a: b: a<b)
        (map
          (c: lib.concatStringsSep "." c.passthru.spath)
          finalAttrs.passthru.after)))) +
  extraCommands;
})
