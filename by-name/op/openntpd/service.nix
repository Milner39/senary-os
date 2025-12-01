{ lib
, six
, pkgs
, targets

# This requires 0001-libressl-make-stateDir-a-parameter-expose-all-parame.patch
# which is not (yet) in upstream nixpkgs
, package ? pkgs.openntpd.override {
  # Ensure that all state files are kept in /run so everything is ephemeral
  # and we can `mkdir` all the requisite directories without having to worry
  # about whether or not / has been remounted read-write.

  stateDir = "/run/openntpd";
}
, conf ? throw "you must provide the path to an ntp.conf file"
}:
let
  # FIXME: verify that privsepUser is in host.users
  # FIXME: verify that privsepPath is the home directory of that user
  inherit (package.passthru) stateDir privsepPath privsepUser;
in
assert lib.hasPrefix "/run/" stateDir;
six.mkFunnel {
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

  run = pkgs.writeScript "run" ''
#!${pkgs.runtimeShell}
exec 2>&1

echo 0.0 > ${stateDir}/db/ntpd.drift
${pkgs.busybox}/bin/busybox chown -R ${privsepUser} ${stateDir}/db
${pkgs.busybox}/bin/busybox chown -R ${privsepUser} ${stateDir}/run
exec ${package}/bin/ntpd -s -d -f ${conf}
'';
}
