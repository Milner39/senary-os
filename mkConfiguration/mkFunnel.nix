{ lib
, pkgs
, six
, timeout-up   ? null # milliseconds
, timeout-down ? null # milliseconds

, run    ? throw "you must set run"
, finish ? null

, notification-fd ? null
, lock-fd ? null
, timeout-kill ? null
, timeout-finish ? null
, max-death-tally ? null
, down-signal ? null

# spawn supervised process in a new PID namespace
, flag-newpidns ? false

, up    ? null
# down is not allowed -- s6-rc creates its own ./down
, data  ? null # copied verbatim
, env   ? null # copied verbatim
, passthru ? {}
}@args:
assert up!=null   -> lib.isPath up || lib.isDerivation up;
assert data!=null -> lib.isPath data || lib.isDerivation data || lib.isAttrs data;
assert env!=null  -> lib.isPath env || lib.isDerivation env || lib.isAttrs env;

assert flag-newpidns ->
       pkgs.stdenv.hostPlatform.isLinux &&
       lib.versionAtLeast pkgs.s6.version "2.13.1.0";

let

  env' =
    if env==null || lib.isPath env || lib.isDerivation env
    then env
    else if !(lib.isAttrs env)
    then throw "env must be null, a path, a derivation, or an attrset of strings"
    else lib.pipe env [
      (lib.mapAttrs
        (key: value:
          let val =
                if lib.isString value
                then value
                else if lib.isInt value
                then toString value
                else throw "when env is an attrset, its values must be strings or integers";
          in ''
            echo ${lib.escapeShellArg val} > $out/${lib.escapeShellArg key}
          ''))
      (lib.mapAttrsToList (_: v: v))
      (lines: pkgs.runCommand "six-env" {} (lib.concatStrings ([''
        mkdir $out
      ''] ++ lines)))
      (drv: drv.outPath)
    ];
in
(six.mkService {
  inherit timeout-up timeout-down up;
  down = null;
  passthru = (args.passthru or {}) // {
    inherit data env;
  };
  type = "longrun";
  extraCommands = "";
}).overrideAttrs(finalAttrs: previousAttrs:
  let
    final-sname = lib.concatStringsSep "." finalAttrs.passthru.spath;
  in {
  buildCommand = (previousAttrs.buildCommand or "") + ''
  '' + lib.optionalString (timeout-kill != null) ''
    echo ${timeout-kill} > $out/timeout-kill
  '' + lib.optionalString (timeout-finish != null) ''
    echo ${timeout-finish} > $out/timeout-finish
  '' + ''
    ln -s ${six.util.scriptify { name = "target.${final-sname}.run"; } run} $out/run
  '' + lib.optionalString (finish != null) ''
    ln -s ${six.util.scriptify { name = "target.${final-sname}.finish"; } finish} $out/finish
  '' + lib.optionalString (data != null && (!(lib.isAttrs data) || lib.isDerivation data)) ''
    ln -s ${data} $out/data
  '' + lib.optionalString (data != null && lib.isAttrs data && !(lib.isDerivation data)) ''
    mkdir $out/data
    ${lib.pipe data [
      (lib.mapAttrs (k: v: if lib.isInt v then toString v else v))
      (lib.mapAttrsToList (k: v:
        if lib.isString v
        then "echo ${lib.escapeShellArg v} > $out/data/${lib.escapeShellArg k}"
        else if (lib.isDerivation v || lib.isPath v)
        then "ln -s ${v} $out/data/${lib.escapeShellArg k}"
        else throw "when data is an attrset, attrvalues must be strings, ints, paths, or derivations; encountered ${lib.typeOf v} at ${k}"
      ))
      (lib.concatStringsSep "\n")
    ]}
  '' + lib.optionalString (env' != null) ''
    ln -s ${env'} $out/env
  '' + lib.optionalString (env' == null && lib.isAttrs run && !(lib.isDerivation run)) ''
    mkdir $out/env
  '' + lib.optionalString flag-newpidns ''
    touch $out/flag-newpidns
  '' + lib.optionalString (notification-fd != null) ''
    echo '${toString notification-fd}' > $out/notification-fd
  '';
})
