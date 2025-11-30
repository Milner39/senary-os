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
    #listen-address = "127.0.0.1";
    disable-upnp = null;
    execution-endpoint = geth.passthru.endpoint;
    execution-jwt = geth.passthru."authrpc.jwtsecret";
    #checkpoint-sync-url = "https://mainnet.checkpoint.sigp.io";
    allow-insecure-genesis-sync = null;
  };

in
six.mkFunnel {

  env = {
    NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };

  run = {
    inherit (geth) user group;
    argv = [
      "${package}/bin/lighthouse"
      "beacon_node"
    ] ++ six.lib.attrsToFlags (defaultConfig // extraConfig) ;
  };

  passthru = {
    after = [ geth ];
  };
}

