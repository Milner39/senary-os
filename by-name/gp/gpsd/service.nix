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

  package = package'.override {
    gpsdUser = user;
    gpsdGroup = group;
  };

  options = [
    "-b"                        # bluetooth-safe: open data sources read-only
    "-n"                        # don't wait for client connects to poll GPS
    "-N"                        # don't go into background
    "-F" gpsd-socket            # specify control socket location
    "-G"                        # make gpsd listen on INADDR_ANY
    "-D" debug-level            # set debug level
    "-S" (toString daemon-port) # set port for daemon
    gps-device
  ];

  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    chown ${user}:${group} ${gps-device}
    #rm -rf /var/run/gpsd/
    mkdir -p /var/run/gpsd/
    mkdir -p /run/gpsd/
    chown ${user}:${group} /var/run/gpsd/
    chown ${user}:${group} /run/gpsd/
    exec ${package}/bin/gpsd ${lib.escapeShellArgs options}
  '';

in six.mkFunnel {
  passthru = passthru // {
    after = (passthru.after or []) ++ [ targets.global.coldplug ];
    inherit gpsd-socket user group;
  };
  inherit run;
}
