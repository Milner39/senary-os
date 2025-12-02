{ lib
, pkgs
, six
, targets
, hostname ? throw "missing hostname"
}:
six.mkOneshot {

  # FIXME: make sure both the hostname and `localhost` are in `/etc/hosts`
  up = [
    "${pkgs.busybox}/bin/sysctl"
    "kernel.hostname=${hostname}"
  ];

  passthru.before = [ targets.global.set-hostname ];

  passthru.after = [
    targets.mounts.sys
    targets.mounts.proc
  ];

}
