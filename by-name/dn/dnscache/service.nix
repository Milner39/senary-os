{ lib
, six
, pkgs
, targets
, package ? pkgs.djbdns
, user ? "_dnscache"
, group ? "_dnscache"
, cache-size ? 10000
, listen-ip ? "127.0.0.1"
, outbound-ip ? "0.0.0.0"   # 0.0.0.0 means let the kernel decide

# if non-null: act as a stub resolver, and forward queries to specified servers
# if null: act as a recursive resolver
, forward-queries-to ? null
, root-servers ? null
}:

# TODO: block queries to .in-addr.arpa. except for *.127.in-addr.arpa

# Useful: "If there are addresses listed in servers/moon.af.mil, for
# example, then dnscache will send queries for anything.moon.af.mil to
# those addresses, and will not cache records for anything.moon.af.mil
# from outside servers such as the root servers."

# Notes:
# - dnscache handles localhost internally, giving it an A record of 127.0.0.1.
# - dnscache handles 1.0.0.127.in-addr.arpa internally, giving it a PTR record of localhost.
# - dnscache handles dotted-decimal domain names internally, giving (e.g.) the domain name 192.48.96.2 an A record of 192.48.96.2.

let

  error-message =
    "exactly one of root-servers or forward-queries-to must be non-null";
  servers =
    if root-servers != null
    then
      assert !(forward-queries-to==null)
              -> throw "you cannot specify both of forward-queries-to and root-servers";
      root-servers
    else if forward-queries-to != null
    then forward-queries-to
    else throw "you cannot leave both forward-queries-to and root-servers unspecified";

  servers-file =
    pkgs.writeText "dnscache-servers"
      (lib.concatStringsSep "\n" servers);
in

six.mkFunnel {
  inherit user group;
  do-not-call-setuid = true;

  data = {
  };

  env = {
    FORWARDONLY = if forward-queries-to == null then "0" else "1";
    UID = user;
    GID = group;
    CACHESIZE = toString cache-size;
    IP = listen-ip;
    IPSEND = outbound-ip;
    ROOT = "./data";
  };

  run.pre-argvs = [
    ( six.util.execline.ignore-exit-code [
      "${pkgs.busybox}/bin/busybox" "chattr" "-f" "-i" "/etc/resolv.conf"
    ])
    [ "${pkgs.execline}/bin/redirfd" "-w" "1" "/etc/resolv.conf"
      "${pkgs.busybox}/bin/busybox" "echo" "nameserver 127.0.0.1" ]
    [ "${pkgs.busybox}/bin/busybox" "chattr" "+i" "/etc/resolv.conf" ]

    # dnscache seems to get upset if these are symlinks rather than files...

    # FIXME apparently this is a non-disableable filtering mechanism for client IPs,
    # but it can only be configured at 8-bit-netmask-chunk granularity?
    [ "${pkgs.busybox}/bin/mkdir" "-p" "data/ip/" ]
    [ "${pkgs.busybox}/bin/touch" "data/ip/127.0.0.1" ]

    # TODO: validate that these are numerical ipv4 addresses at eval-time
    [ "${pkgs.busybox}/bin/mkdir" "-p" "data/servers/" ]
    [ "${pkgs.busybox}/bin/cp" servers-file "data/servers/@" ]
  ];

  run.redirect-stdin-from = "/dev/urandom";

  run.argv = [ "${package}/bin/dnscache" ];

  passthru.after = [ targets.global.coldplug ]; # for /dev/urandom
}
