{ lib
, six
, pkgs
, targets

, name
, blockdev-targets
}:

six.mkOneshot {

  up = [
    "${lib.getBin pkgs.lvm2}/bin/lvm"
    "lvchange"
    "-ay"
    name
  ];

  down = six.util.execline.ignore-exit-code [
    "${lib.getBin pkgs.lvm2}/bin/lvm"
    "lvchange"
    "-an"
    name
  ];

  passthru.after = [
    targets.mounts.proc
    targets.mounts.sys
    targets.global.coldplug
  ] ++ blockdev-targets;

}
