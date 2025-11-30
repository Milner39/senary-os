{ lib
, pkgs
, six
, targets
, package ? pkgs.monero-cli
, user ? "monerod"
, group ? "monerod"
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

  run = {
    inherit user;
    inherit group;
    argv = [
      "${package}/bin/monerod"
    ] ++ args;
  };

  passthru.after = [ targets.global.coldplug ];

}

