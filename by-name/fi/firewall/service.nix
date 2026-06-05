{ lib
, pkgs
, six
, targets
, host
, flush-old-ruleset ? true
, ruleset ? ""
, forwards ? []
, tables ? []

# names of modules (usually netfilter) to insert before bringing the firewall up
, modules ? []
}:

let
  ruleset-file = builtins.toFile "nftables-ruleset"
    (lib.optionalString flush-old-ruleset ''
      flush ruleset
      ${ruleset}
      ${lib.pipe forwards [
         (lib.map (host.site.globals.forward-port-nftables host))
         (t: t ++ tables)
         (lib.map six.lib.mkNetfilterTable)
         (lib.concatStringsSep "\n")
       ]}
    '');
in
six.mkOneshot {
  up = pkgs.writeScript "firewall-up" (''
    #!${pkgs.runtimeShell} -e

  '' + lib.optionalString (modules != []) ''
    ${pkgs.kmod}/bin/modprobe --all ${lib.escapeShellArgs modules}
  '' + ''

    ${pkgs.nftables}/bin/nft -f ${ruleset-file} || exit -1
    # it is extremely important that the following line is not executed unless
    # the previous line succeeds!
    ${pkgs.busybox}/bin/echo -n 1 > /proc/sys/net/ipv4/ip_forward
  '');

  down = pkgs.writeScript "firewall-down" ''
    #!${pkgs.runtimeShell}
    ${pkgs.busybox}/bin/echo -n 0 > /proc/sys/net/ipv4/ip_forward
    # s6 does not have much support for recovering from a oneshot "down" script
    # which fails.  Therefore we do as little as possible here.
  '';

  passthru = {
    after = with targets; [
      mounts.proc
    ];
  };
}
