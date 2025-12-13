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


let

  args = lib.mapAttrsToList
    (k: v: if v==true then "--${k}" else "--${k}=${v}")
    ({
      data-dir = datadir;
      non-interactive = true;
    } // extraArgs);
in

six.mkFunnel {

  inherit user group;
  run = {
    argv = [
      "${package}/bin/monerod"
    ] ++ args;
  };

  passthru.after = [ targets.global.coldplug ];

}

