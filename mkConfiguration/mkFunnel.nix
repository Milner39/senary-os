{ lib
, pkgs
, six
, host

, run    ? throw "you must set run"

# The finish script is executed with four arguments:
#
# 1. the exit code from the run script (resp. 256 if the run script was killed
#    by a signal)
#
# 2. an undefined number (resp. the number of the signal that killed the run
#    script)
#
# 3. the name of the service directory, the same that has been given to ./run
#
# 4. the process group id of the defunct run script. This is useful to clean up
#    services that leave children behind: for instance, if test "$1" -gt 255 ;
#    then kill -9 -- -"$4" ; fi in the finish script will SIGKILL all children
#    processes if the service crashed. This is not an entirely reliable
#    mechanism, because an annoying service could spawn children processes in a
#    different process group, but it should catch most offenders.
#
, finish ? null

, timeout-up   ? null   # milliseconds, only applies to readiness
, timeout-kill ? null   # milliseconds, how long to wait after SIGTERM before sending SIGKILL
, timeout-finish ? null # milliseconds, timeout for ./finish script

, notification-fd ? null
, lock-fd ? null
, max-death-tally ? null
, down-signal ? null

# spawn supervised process in a new PID namespace
, flag-newpidns ? false

, up    ? null
# down is not allowed -- s6-rc creates its own ./down
, data  ? null # copied verbatim
, env   ? null # copied verbatim

, user ? 0
, group ? if user==0 then 0 else host.users.${user}.gid
, extra-groups ? []

# true if the service calls setuid() itself and needs to be started as root
, do-not-call-setuid ? false

  # create (`mkdir -p`) a directory for each attrname, with uid/gid set to
  # user/group, and mode set to the attrvalue (an octal string).  This will
  # happen before the pre-argv.
, mkdir ? {}

, passthru ? {}
}@args:
assert up!=null   -> lib.isPath up || lib.isDerivation up;
assert data!=null -> lib.isPath data || lib.isDerivation data || lib.isAttrs data;
assert env!=null  -> lib.isPath env || lib.isDerivation env || lib.isAttrs env;

assert flag-newpidns ->
       pkgs.stdenv.hostPlatform.isLinux &&
       lib.versionAtLeast pkgs.s6.version "2.13.1.0";

assert (lib.isAttrs run && run?user) -> throw "please set user in mkFunnel, not in run";
assert (lib.isAttrs finish && finish?user) -> throw "please set user in mkFunnel, not in finish";

assert passthru?user -> throw "please pass `user`, not `passthru.user`, to mkFunnel";
assert passthru?group -> throw "please pass `group`, not `passthru.group`, to mkFunnel";

let

  extra-gids =
    if extra-groups==null
    then null
    else lib.map
      (g: if lib.isString g
          then host.groups.${g}.gid
          else g)
      extra-groups;

  scriptify =
    { name
    , argMode ? "var"
    , readNArgs
    }:
    script:
    let
      chpst = {
        redirect-stderr-to-stdout = true;
      } // lib.optionalAttrs (env != null) {
        envdir = "./env";
      } // lib.optionalAttrs (user != null && !do-not-call-setuid) {
        # TODO: if (lib.isString user), check that this exists in host.users
        inherit user;
      } // lib.optionalAttrs (group != null && !do-not-call-setuid) {
        inherit group;
      } // lib.optionalAttrs (extra-gids != null && !do-not-call-setuid) {
        inherit extra-gids;
      } // {
        pre-argvs = [];

        # TODO: consider these
        #dir ? null,
        #env-clear = true,
      } //
      (if   lib.isString script || lib.isDerivation script || lib.isPath script
       then { argv = [ (toString script) ]; }
       else script);

      # TODO: check that we don't change the ownership of globally-known
      # directories like /etc/secrets, /run, etc
      mkdir-argvs = lib.pipe mkdir [
        (lib.mapAttrsToList
          (path: mode: [
            [ "${pkgs.busybox}/bin/busybox" "mkdir" "-p" "-m" mode path ]
          ] ++ lib.optionals (!(user == 0 && group == 0)) [
            [ "${pkgs.busybox}/bin/busybox" "chown" "${toString user}:${toString group}" path ]
          ]))
        lib.concatLists
      ];

    in
      six.util.depot.writeExecline name
      { inherit argMode readNArgs; }
      (six.util.chpst
        (chpst // { pre-argvs = mkdir-argvs ++ chpst.pre-argvs; }));

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
  inherit timeout-up up;
  down = null;
  passthru = {
    inherit data env user group;
    #inherit groups;
  } // (args.passthru or {});
  type = "longrun";
  extraCommands = "";
}).overrideAttrs(finalAttrs: previousAttrs:
  let
    final-sname = lib.concatStringsSep "." finalAttrs.passthru.spath;
  in {
  buildCommand = (previousAttrs.buildCommand or "") + ''
  '' + lib.optionalString (timeout-kill != null) ''
    echo ${toString timeout-kill} > $out/timeout-kill
  '' + lib.optionalString (timeout-finish != null) ''
    echo ${toString timeout-finish} > $out/timeout-finish
  '' + lib.optionalString (down-signal != null) ''
    echo ${toString down-signal} > $out/down-signal
  '' + ''
    ln -s ${scriptify { name = "target.${final-sname}.run"; readNArgs = 1; } run} $out/run
  '' + lib.optionalString (finish != null) ''
    ln -s ${scriptify { name = "target.${final-sname}.finish"; readNArgs = 4; } finish} $out/finish
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
    cp -r ${env'} $out/env
  '' + lib.optionalString flag-newpidns ''
    touch $out/flag-newpidns
  '' + lib.optionalString (notification-fd != null) ''
    echo '${toString notification-fd}' > $out/notification-fd
  '';
})
