{ lib
, pkgs
, six
, targets
, package ? pkgs.bitcoind
, user ? "_bitcoind"
, group ? "_bitcoind"
, datadir ? throw "you must specify datadir"
, extraConfig ? {}
}:

let

  writeBitcoindConfig = attrs:
    lib.pipe attrs [
      (lib.mapAttrsToList (k: v: "${k}=${if lib.isString v then v else toString v}"))
      (lib.concatStringsSep "\n")
    ];

  config = {
    inherit datadir;
    rpccookiefile = "${datadir}/rpc-cookie";
    printtoconsole = true;
    disablewallet = true;
    nodebuglogfile = true;
    rpccookieperms = "group";  # readable-by
  } // extraConfig;

in

assert config?rpcbind && !(config?rpcallowip)
  -> throw "-rpcbind is ignored if -rpcallowip is missing";

six.mkFunnel {

  inherit user group;
  run = {
    argv = [
      "${package}/bin/bitcoind"
      "-conf=${pkgs.writeText "bitcoind.conf" (writeBitcoindConfig config)}"
    ];
  };

  passthru = {
    after = [ targets.global.coldplug ];
    inherit datadir;
    inherit config;
  };
}

