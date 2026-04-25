{ lib
, six
, pkgs
, targets

, user ? "_ntpd"
, group ? "_ntpd"

# This requires 0001-libressl-make-stateDir-a-parameter-expose-all-parame.patch
# which is not (yet) in upstream nixpkgs
, package ? pkgs.openntpd.override {
  # Ensure that all state files are kept in /run so everything is ephemeral
  # and we can `mkdir` all the requisite directories without having to worry
  # about whether or not / has been remounted read-write.

  stateDir = "/run/openntpd";
  privsepUser = user;
}
, conf ? throw "you must provide the path to an ntp.conf file"
}:
let
  # FIXME: verify that privsepUser is in host.users
  # FIXME: verify that privsepPath is the home directory of that user
  inherit (package.passthru) stateDir privsepPath;
in
assert lib.hasPrefix "/run/" stateDir;
six.mkFunnel {
  inherit user group;
  do-not-call-setuid = true;

  passthru.after = [
    targets.global.coldplug

    # on startup: copy hwclock to sysclock before starting openntpd
    # on shutdown: copy sysclock to hwclock after stopping openntpd
    targets.global.hwclock
  ];

  mkdir = {
    "${stateDir}/db" = "0700";
    "${stateDir}/run" = "0700";
  };

  run.pre-argvs = [
    # ntpd.drift cannot be empty
    [ "${pkgs.execline}/bin/redirfd" "-w" "1" "${stateDir}/db/ntpd.drift"
      "${pkgs.busybox}/bin/busybox" "echo" "0" ]
  ];

  run.argv = [
    "${package}/bin/ntpd" "-d" "-f" "${conf}"
  ];
}
