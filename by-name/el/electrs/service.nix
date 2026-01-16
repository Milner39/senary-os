{ lib
, pkgs
, six
, targets
, package ? pkgs.electrs
, user ? "_electrs"
, group ? "_bitcoind"
, datadir ? throw "you must specify datadir"
, bitcoind ? throw "you must specify targets.bitcoind"
, network ? "bitcoin"
, electrum-rpc-addr ? throw "you must specify electrum-rpc-addr"
, monitoring-addr ? "127.0.0.1:4224"
, daemon-rpc-addr ? bitcoind.passthru.config.daemon-rpc-addr or "127.0.0.1:8332"
, daemon-p2p-addr ? "${bitcoind.passthru.config.bind}:8333"
, extraArgs ? {}
}:


six.mkFunnel {

  inherit user group;

  run.argv = [
    "${package}/bin/electrs"
  ] ++ six.lib.attrsToFlags ({
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

  passthru.after = [ bitcoind ];

}

