{ lib
, pkgs
, six
, targets
, package ? pkgs.go-ethereum
, user ? "_geth"
, group ? "_geth"
, dataDir ? "/var/service/geth"
, extraConfig ? {}
}:

let
  config = {
    datadir = dataDir;
    usb = "false";
    "authrpc.jwtsecret" = "/run/geth/secret.jwt";
    "authrpc.addr" = "127.0.0.1";
    "authrpc.port" = "8551";
  } // extraConfig;
in
six.mkFunnel {

  timeout-kill = 15000;   # geth sometimes takes a long time to shut down

  inherit user;
  inherit group;

  run.pre-argvs = [
    [ "${pkgs.busybox}/bin/mkdir" "-m" "0700" "-p" (builtins.dirOf config."authrpc.jwtsecret") ]
    [ "${pkgs.busybox}/bin/chown" "${user}:${group}" (builtins.dirOf config."authrpc.jwtsecret") ]
    [ "${pkgs.busybox}/bin/chmod" "0700" (builtins.dirOf config."authrpc.jwtsecret") ]
    [ "${pkgs.execline}/bin/redirfd" "-w" "1" config."authrpc.jwtsecret"
      "${pkgs.util-linux}/bin/hexdump" "-n" "32" "-e" "8 \"%08x\" 1 \"\\n\"" "/dev/random" ]
  ];

  run.argv = [
    "${package}/bin/geth"
  ] ++ six.lib.attrsToFlags config;

  passthru = {
    after = [ targets.global.coldplug ];
    inherit user group;
    endpoint = "http://${config."authrpc.addr"}:${config."authrpc.port"}";
    inherit (config) "authrpc.jwtsecret";
  };
}

