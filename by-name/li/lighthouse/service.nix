{ lib
, pkgs
, six
, targets
, package ? pkgs.lighthouse
, execution-layer-node ? throw "you must pass targets.execution-layer-node"
, dataDir ? "/var/service/lighthouse"
, extraConfig ? {}
}:

let

  defaultConfig = {
    datadir = dataDir;
    disable-upnp = null;
    execution-endpoint = execution-layer-node.passthru.endpoint;
    execution-jwt = execution-layer-node.passthru."authrpc.jwtsecret";
    checkpoint-sync-url = "https://mainnet.checkpoint.sigp.io";
    #allow-insecure-genesis-sync = null;
  };

in
six.mkFunnel {

  inherit (execution-layer-node) user group;
  env = {
    SSL_CERT_FILE = "/run/current-system/etc/pki/tls/certs/ca-bundle.crt";
  };

  mkdir = {
    "${dataDir}" = "0700";
  };

  run.argv = [
    "${package}/bin/lighthouse"
    "beacon_node"
  ] ++ six.lib.attrsToFlags (defaultConfig // extraConfig);

  # lighthouse will create the jwt secrets file if it does not exist
  passthru.before = [ execution-layer-node ];
  passthru.after = [ targets.global.coldplug ];
}

