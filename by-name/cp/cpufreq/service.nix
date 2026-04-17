{ lib
, pkgs
, six
, targets

, governor ? null
, min ? null
, max ? null
}:
six.mkOneshot {
  up = [
    "${pkgs.linuxPackages.cpupower}/bin/cpupower" "frequency-set"
  ] ++ lib.optionals (governor != null) [
    "--governor" governor
  ] ++ lib.optionals (min != null) [
    "--min" (toString min)
  ] ++ lib.optionals (max != null) [
    "--max" (toString max)
  ];

  passthru.after = [
    targets.global.coldplug    # maybe, if needed
  ];
}
