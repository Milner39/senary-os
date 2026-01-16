{ lib
, pkgs
, six
, targets
, package ? pkgs.monero-cli
, user ? "_monerod"
, group ? "_monerod"
, datadir ? throw "you must specify datadir"
, extraArgs ? {}
}:

six.mkFunnel {

  inherit user group;
  run.argv = [
    "${package}/bin/monerod"
  ] ++ six.lib.attrsToFlags ({
    data-dir = datadir;
    non-interactive = true;
  } // extraArgs);

  passthru.after = [ targets.global.coldplug ];

}

