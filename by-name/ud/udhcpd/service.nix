{ lib
, six
, pkgs
, targets
, package ? pkgs.busybox
, user-name ? "_udhcpd"
, group-name ? "_udhcpd"
, instance-name ? "default"
, interface ? throw "interface is required"
, nameservers ? null
, ntp-server ? null
, dhcp-range ? null
, gw ? null
, subnet ? throw "subnet is required"
, dhcp ? {}  # static leases
}:

# FIXME: do a typecheck on `interface`

let
  options = {
    interface = interface.ifname;
    pidfile = "/run/udhcpc/${instance-name}/udhcpd.pid";
    lease_file = "/run/udhcpc/${instance-name}/udhcpd.leases";
    "option subnet" = subnet;

    # leases file is written every this-many seconds (or not at all if zero)
    auto_time = 0;
  } // lib.optionalAttrs (dhcp-range != null) {
    start = dhcp-range.start;
    end = dhcp-range.end;

  } // lib.optionalAttrs (dhcp-range != null && dhcp-range?lease-time) {
    offer_time = dhcp-range.lease-time;
    "option lease" = dhcp-range.lease-time;

  } // lib.optionalAttrs (ntp-server != null) {
    "opt timesrv" = ntp-server;

  } // lib.optionalAttrs (nameservers != null && nameservers != []) {
    "opt dns" = lib.concatStringsSep " " nameservers;

  } // {
    #max_leases = 254

    # The amount of time that an IP will be reserved (leased to nobody)  if a DHCP decline message is received (seconds)
    #decline_time = 3600;

    # The amount of time that an IP will be reserved if an ARP conflict occurs (seconds)
    #conflict_time = 3600;

    # If client asks for lease duration below this value, it will be rounded up to this value (seconds)
    #min_lease = 60;

    # Every time udhcpd writes a leases file, the below script will be called
    #notify_file = "dumpleases";

    # bootp-specific options
    #siaddr = "192.168.0.22";
    #sname = "tftp-server-name";
    #boot_file ="tftp-boot-file-name";

    "opt router" = gw;

    #"opt wins" = "192.168.10.10";
    #"option domain" = "local";
    #"option msstaticroutes" = "10.0.0.0/8 10.127.0.1"     # single static route
    #"option staticroutes" = "10.0.0.0/8 10.127.0.1, 10.11.12.0/24 10.11.12.1"
    #"option 0x08" = "01020304"  # option 8: "cookie server IP addr: 1.2.3.4"

    /*
    "opt subnet" = "IP";
    "opt broadcast" = "IP";
    "opt ipttl" = "NUM";
    "opt mtu" = "NUM";
    "opt hostname" = "STRING";    # client's hostname
    "opt domain" = "STRING";      # client's domain suffix
    "opt search" = "STRING_LIST"; # search domains
    "opt nisdomain" = "STRING";
    "opt timezone" = "NUM";       # (localtime - UTC_time) in seconds. signed
    "opt tftp" = "STRING";        # tftp server name
    "opt bootfile" = "STRING";    # tftp file to download (e.g. kernel image)
    "opt bootsize" = "NUM";       # size of that file
    "opt rootpath" = "STRING";    # (NFS) path to mount as root fs
    "opt wpad" = "STRING";
    "opt serverid" = "IP";        # default: server's IP
    "opt message" = "STRING";     # error message (udhcpd sends it on success too)
    "opt vlanid" = "NUM";         # 802.1P VLAN ID
    "opt vlanpriorit" = "y NUM";  # 802.1Q VLAN priority

    # Options specifying server(s)
    "opt wins" = "IP_LIST";
    "opt nissrv" = "IP_LIST";
    "opt ntpsrv" = "IP_LIST";
    "opt lprsrv" = "IP_LIST";
    "opt swapsrv" = "IP";

    # Options specifying routes
    "opt routes" = "IP_PAIR_LIST";

    # Obsolete options, no longer supported
    "opt logsrv" = "IP_LIST";     # 704/UDP log server (not syslog!)
    "opt namesrv" = "IP_LIST";    # IEN 116 name server, obsolete (August 1979!!!)
    "opt cookiesrv" = "IP_LIST";  # RFC 865 "quote of the day" server, rarely (never?) used
    */
  };

  conf-file =
    builtins.toFile "udhcpd-${instance-name}.conf"
      (lib.pipe options [
        (lib.mapAttrsToList (k: v: "${k} ${toString v}\n"))
        (list: list ++
               (lib.mapAttrsToList (macaddr: ip: "static_lease ${macaddr} ${ip}\n") dhcp))
        lib.concatStrings
      ]);

in six.mkFunnel {
  user = user-name;
  group = group-name;
  do-not-call-setuid = true;

  mkdir = {
    "/run/udhcpc/${instance-name}" = "0700";
  };

  passthru.after = [
    targets.global.coldplug  # for /dev/urandom
  ];

  run.argv = [
    "${package}/bin/udhcpd"
    "-f" # foreground
    "${conf-file}"
  ];
}
