{ lib
, pkgs
, six
, targets
, package ? pkgs.lighthouse
, geth ? throw "you must pass targets.geth"
, dataDir ? "/var/service/lighthouse"
, extraConfig ? {}
}:

let

  defaultConfig = {
    datadir = dataDir;
    disable-upnp = null;
    execution-endpoint = geth.passthru.endpoint;
    execution-jwt = geth.passthru."authrpc.jwtsecret";
    checkpoint-sync-url = "https://mainnet.checkpoint.sigp.io";
    #allow-insecure-genesis-sync = null;
  };

in
six.mkFunnel {

  inherit (geth) user group;
  env = {
    NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };

  run = {
    argv = [
      "${package}/bin/lighthouse"
      "beacon_node"
    ] ++ six.lib.attrsToFlags (defaultConfig // extraConfig) ;
  };

  passthru = {
    after = [ geth ];
  };
}

