{ lib
, pkgs
, six
, targets
, package ? pkgs.reth
, binary-name ? "reth"
, user ? "_reth"
, group ? "_reth"
, dataDir ? "/var/service/reth"
, extraConfig ? {}
, early-args ? [ "node" ]
}:

let
  config = {
    full = null;
    datadir = dataDir;
    "authrpc.jwtsecret" = "/run/reth/secret.jwt";
    "authrpc.addr" = "127.0.0.1";
    "authrpc.port" = "8551";

    "log.file.directory" = "${dataDir}/logs";

    # TODO: use this
    "ipcpath" = "/run/reth/reth.ipc";
  } // extraConfig;
in
six.mkFunnel {

  inherit user;
  inherit group;

  mkdir = {
    "${builtins.dirOf config."authrpc.jwtsecret"}" = "0700";
    "${dataDir}" = "0700";
  };

  /*
  run.pre-argvs = [
    [ "${pkgs.execline}/bin/redirfd" "-w" "1" config."authrpc.jwtsecret"
      "${pkgs.util-linux}/bin/hexdump" "-n" "32" "-e" "8 \"%08x\" 1 \"\\n\"" "/dev/random" ]
  ];
  */

  run.argv = [
    "${package}/bin/${binary-name}"
  ]
  ++ early-args
  ++ six.lib.attrsToFlags config;

  passthru = {
    after = [ targets.global.coldplug ];
    endpoint = "http://${config."authrpc.addr"}:${config."authrpc.port"}";
    inherit (config) "authrpc.jwtsecret";
  };
}

