{ lib
, pkgs
, six
, targets
, package         ? pkgs.gpsd
, user            ? "_gpsd"
, group           ? "_gpsd"
, gpsd-socket     ? throw "missing argument: gpsd-socket"
, gps-device      ? throw "missing argument: gps-device"
, debug-level     ? 3
, daemon-port     ? 2947
, passthru        ? {}
}:

let package' = package; in

let

  package = (package'.override {
    gpsdUser = user;
    gpsdGroup = group;
  }).overrideAttrs(previousAttrs: {
    patches = previousAttrs.patches or [] ++ [
      # gpsd's man page says logs to go stdout when `--foreground` is used, but
      # it doesn't behave that way if `getpid() == getsid(getpid())`
      ./patches/do-not-use-setsid-to-detect-daemonization.patch
    ];
  });

in six.mkFunnel {

  inherit user group;
  do-not-call-setuid = true;

  passthru = passthru // {
    after = (passthru.after or []) ++ [ targets.global.coldplug ];
    inherit gpsd-socket;
  };

  mkdir = {
    ${builtins.dirOf gpsd-socket} = "0644";
    "/run/gpsd/"                  = "0644";
  };

  run.argv = [
    "${package}/bin/gpsd"
    "-b"                        # bluetooth-safe: open data sources read-only
    "-n"                        # don't wait for client connects to poll GPS
    "-N"                        # don't go into background
    "-F" gpsd-socket            # specify control socket location
    "-G"                        # make gpsd listen on INADDR_ANY
    "-D" (toString debug-level) # set debug level
    "-S" (toString daemon-port) # set port for daemon
    gps-device
  ];
}
