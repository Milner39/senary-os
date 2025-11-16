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
    listen-address = "127.0.0.1";
    disable-upnp = null;
    execution-endpoint = geth.passthru.endpoint;
    execution-jwt = geth.passthru."authrpc.jwtsecret";
    #checkpoint-sync-url = "https://mainnet.checkpoint.sigp.io";
    allow-insecure-genesis-sync = null;
  };

in
six.mkFunnel {

  run =
    six.util.depot.writeExecline
      "service.lighthouse.run"
      { argMode = "none"; }
      (six.util.chpst {
        inherit (geth) user group;
        argv = [
          "${package}/bin/lighthouse"
          "beacon_node"

        ] ++ lib.pipe (defaultConfig // extraConfig) [
          (lib.mapAttrsToList
            (key: val:
              "--${key}${lib.optionalString (val!=null) ("=" + lib.escapeShellArg (six.lib.toString val))}"))
        ];
      });

  passthru = {
    after = [ geth ];
  };
}

