{ lib
, yants
, infuse
, ...
}:

# FIXME: move all of this edgerouter-specific stuff into `plat-er{4,6,8,12}.nix`
# since it doesn't apply to any other MIPSen
final: prev: infuse prev ({
  boot.kernel.package.__input.patches.__append = [
    rec {
      name = "110-er200-ethernet_probe_order.patch";
      patch = final.pkgs.fetchpatch {
        inherit name;
        url = "https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob_plain;"+
              "f=target/linux/octeon/patches-5.4/110-er200-ethernet_probe_order.patch;"+
              "hb=02e2723ef317c65b6ddfc70144b10f9936cfc2af";
        sha256 = "sha256-oumgFtZnuFL2MXWtUd5RipF+qDHuze+wG/ogjtcd5XQ=";
      };
    }

    # this patch is needed in order to get predictable interface names; it is from openwrt but no longer applies cleanly
    # https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob_plain;f=target/linux/octeon/patches-5.4/700-allocate_interface_by_label.patch
    { name = "700-allocate_interface_by_label.patch"  ; patch = ./patches/700-allocate_interface_by_label.patch; }

    # support for Ubiquiti E100 boards (Cavium CN5020), Edgerouter Lite
    # support for Ubiquiti E120 boards (Cavium CN5020), Unifi Security Gateway 3 (USG-3)
    #{ name = "ubnt_e100-e120.patch"           ; patch = ./patches/ubnt_e100-e120.patch; }

    # support for Ubiquiti E200 board (Cavium CN6120), Edgerouter 8 Pro; SFP cages do not work in Linux
    # support for Ubiquiti E220 board (Cavium CN6120), Unifi Security Gateway Pro-4 (USGPro-4); SFP cages do not work in Linux
    #{ name = "edgerouter-8pro.patch"          ; patch = ./patches/edgerouter-8pro.patch; }

    # support for Ubiquiti E300 board (Cavium CN7130) Edgerouter-4; SFP cages *do* work in Linux
    { name = "edgerouter-4.patch"             ; patch = ./patches/edgerouter-4.patch; }

    # support for Ubiquiti E300 board (Cavium CN7130) Edgerouter-6; SFP cages *do* work in Linux
    # support for Ubiquiti E300 board (Cavium CN7130) Edgerouter-12; SFP cages *do* work in Linux, internal switch behaves strangely
    { name = "edgerouter-6,12.patch"          ; patch = ./patches/edgerouter-6-12.patch; }

  ];

  boot.kernel.package.__output.NIX_CFLAGS_COMPILE.__append = " -w ";
  boot.kernel.package.__output.postInstall.__append = ''
    $STRIP $out/vmlinux-${final.boot.kernel.package.version}
  '';

  boot.kernel.package.__input.structuredExtraConfig = lib.mapAttrs (_: v: { __assign = v; }) {
    CAVIUM_OCTEON_CVMSEG_SIZE = "0";
    CPU_BIG_ENDIAN = "n";
    CPU_LITTLE_ENDIAN = "y";
    PCIEPORTBUS = "y";
    PCIEAER = "y";
    MTD_SPI_NOR = "y";
    MTD_SPI_NOR_USE_4K_SECTORS = "y";
    #PHYLINK = "m";
    #SFP = "m";
    #MDIO_I2C = "m";

    # needed for /dev/mtd{1..} to show up
    MTD_CMDLINE_PARTS = "y";

    # allow use of the .appended_dtb section
    MIPS_ELF_APPENDED_DTB = "y";

    # Didn't get the following to work:
    #
    # Ensures that the DTB chosen/bootparams are extended by, rather than
    # overwritten by, the bootloader's boot arguments.  This lets us put the
    # initrd start/size in the DTB.
    USE_OF = "y";

    MIPS_CMDLINE_FROM_BOOTLOADER = "n";
    MIPS_CMDLINE_DTB_EXTEND = "y";

    STRIP_ASM_SYMS = "y";

    # for vlans on simpson
    VLAN_8021Q = "m";

    # FIXME: never figured out how to make the nft_*.ko modules auto-load
    NF_TABLES = "m";
    NFT_NUMGEN = "m";
    NFT_CT = "m";
    NFT_CONNLIMIT = "m";
    NFT_LOG = "m";
    NFT_LIMIT = "m";
    NFT_MASQ = "m";
    NFT_REDIR = "m";
    NFT_NAT = "m";
    NFT_TUNNEL = "m";
    NFT_QUOTA = "m";
    NFT_REJECT = "m";
    NFT_HASH = "m";
    NFT_SOCKET = "m";
    NFT_OSF = "m";
    NFT_TPROXY = "m";
    NFT_REJECT_IPV4 = "m";
    NF_CONNTRACK = "m";
    NF_LOG_SYSLOG = "m";
    NF_CONNTRACK_MARK = "y";
    NF_CONNTRACK_ZONES = "y";
    # NF_CONNTRACK_PROCFS is not set
    NF_CONNTRACK_EVENTS = "y";
    NF_CONNTRACK_TIMEOUT = "y";
    NF_CONNTRACK_TIMESTAMP = "y";
    NF_CONNTRACK_LABELS = "y";
    NF_CT_PROTO_DCCP = "y";
    NF_CT_PROTO_GRE = "y";
    NF_CT_PROTO_SCTP = "y";
    NF_CT_PROTO_UDPLITE = "y";
    NF_CONNTRACK_AMANDA = "m";
    NF_CONNTRACK_FTP = "m";
    NF_CONNTRACK_H323 = "m";
    NF_CONNTRACK_IRC = "m";
    NF_CONNTRACK_BROADCAST = "m";
    NF_CONNTRACK_NETBIOS_NS = "m";
    NF_CONNTRACK_SNMP = "m";
    NF_CONNTRACK_PPTP = "m";
    NF_CONNTRACK_SANE = "m";
    NF_CONNTRACK_SIP = "m";
    NF_CONNTRACK_TFTP = "m";
    NF_CT_NETLINK = "m";
    NF_CT_NETLINK_TIMEOUT = "m";
    NF_NAT = "m";
    NF_NAT_AMANDA = "m";
    NF_NAT_FTP = "m";
    NF_NAT_IRC = "m";
    NF_NAT_SIP = "m";
    NF_NAT_TFTP = "m";
    NF_NAT_REDIRECT = "y";
    NF_NAT_MASQUERADE = "y";
    NF_TABLES_NETDEV = "y";
    NF_DUP_NETDEV = "m";
    NF_FLOW_TABLE_INET = "m";
    NF_FLOW_TABLE = "m";
    # NF_FLOW_TABLE_PROCFS is not set
    NF_DEFRAG_IPV4 = "m";
    NF_SOCKET_IPV4 = "m";
    NF_TPROXY_IPV4 = "m";
    NF_TABLES_IPV4 = "y";
    NF_TABLES_INET= "y";
    NF_TABLES_ARP = "y";
    NF_DUP_IPV4 = "m";
    NF_LOG_ARP = "m";
    NF_LOG_IPV4 = "m";
    NF_REJECT_IPV4 = "m";
    NF_NAT_SNMP_BASIC = "m";
    NF_NAT_PPTP = "m";
    NF_NAT_H323 = "m";
    NF_CONNTRACK_BRIDGE = "m";

    BRIDGE = "m";
    BRIDGE_NETFILTER = "m";
    BRIDGE_NF_EBTABLES = "y";
    BRIDGE_EBT_BROUTE = "y";
    BRIDGE_EBT_T_FILTER = "y";
    BRIDGE_EBT_T_NAT = "y";
    BRIDGE_EBT_802_3 = "y";
    BRIDGE_EBT_AMONG = "y";
    BRIDGE_EBT_ARP = "y";
    BRIDGE_EBT_IP = "y";
    BRIDGE_EBT_LIMIT = "y";
    BRIDGE_EBT_MARK = "y";
    BRIDGE_EBT_PKTTYPE = "y";
    BRIDGE_EBT_STP = "y";
    BRIDGE_EBT_VLAN = "y";
    BRIDGE_EBT_ARPREPLY = "y";
    BRIDGE_EBT_DNAT = "y";
    BRIDGE_EBT_MARK_T = "y";
    BRIDGE_EBT_REDIRECT = "y";
    BRIDGE_EBT_SNAT = "y";
    BRIDGE_EBT_LOG = "y";
    BRIDGE_IGMP_SNOOPING = "y";
    BRIDGE_EBT_NFLOG = "y";
    BRIDGE_VLAN_FILTERING = "y";
    BRIDGE_MRP = "y";

    #      PHYLIB = "m";
    #      NET_DSA_VITESSE_VSC73XX = "m";
    #      VITESSE_PHY = "y";

    PPP = "m";
    PPP_BSDCOMP = "m";
    PPP_DEFLATE = "m";
    PPP_FILTER= "y";
    #PPP_MPPE = "m";
    #PPP_MULTILINK=y
    PPPOE = "m";
    PPP_ASYNC = "m";
    PPP_SYNC_TTY = "m";
    #HDLC_PPP = "m";
  };
})
