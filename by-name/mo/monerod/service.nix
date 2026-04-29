{ lib
, pkgs
, six
, targets
, package ? pkgs.monero-cli
, user ? "_monerod"
, group ? "_monerod"
, datadir ? "/var/service/monerod"
, extraArgs ? {}
}:

six.mkFunnel {

  inherit user group;

  mkdir = {
    "${datadir}" = "0700";
  };

  run.argv = [
    "${package}/bin/monerod"
  ] ++ six.lib.attrsToFlags ({
    data-dir = datadir;
    non-interactive = null;
  } // extraArgs);

  passthru.after = [ targets.global.coldplug ];

}

