{ lib
, pkgs
, six
, targets
}:
six.mkOneshot {
  # could also write to /proc/sys/net/ipv4/ping_group_range
  up = [
    "${pkgs.busybox}/bin/sysctl"
    "net.ipv4.ping_group_range=0 4294967294"
  ];

  passthru.after = [
    targets.mounts.sys
    targets.mounts.proc
  ];
}
