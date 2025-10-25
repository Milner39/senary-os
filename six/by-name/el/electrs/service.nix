{ lib
, pkgs
, six
, targets
, package ? pkgs.electrs
, user ? "electrs"
, group ? "bitcoind"
, datadir ? throw "you must specify datadir"
, bitcoind ? throw "you must specify targets.bitcoind"
, network ? "bitcoin"
, electrum-rpc-addr ? throw "you must specify electrum-rpc-addr"
, monitoring-addr ? throw "you must specify monitoring-addr"
, daemon-rpc-addr ? throw "you must specify daemon-rpc-addr"
, daemon-p2p-addr ? throw "you must specify daemon-p2p-addr"
, extraArgs ? {}
}:


let

  args = lib.mapAttrsToList
    (k: v: "--${k}=${v}")
    ({
      log-filters = "INFO";
      daemon-dir = bitcoind.passthru.datadir;
      cookie-file = bitcoind.passthru.config.rpccookiefile;
      db-dir = datadir;
      inherit network;
      inherit electrum-rpc-addr;
      inherit monitoring-addr;
      inherit daemon-rpc-addr;
      inherit daemon-p2p-addr;
    } // extraArgs);

in

six.mkFunnel {

  run =
    six.util.depot.writeExecline
      "service.electrs.run"
      { argMode = "none"; }
      (six.util.chpst {
        inherit user;
        inherit group;
        argv = [
          "${package}/bin/electrs"
        ] ++ args;
      });

  passthru.after = [ bitcoind ];

}

