{ lib
, pkgs
, six
, targets
, ifname ? throw "you must specify the interface name"
, phyname ? throw "you must specify the phy name"

, modules ? [ "pcie-rockchip-host" "mwifiex_pcie" ]
#, modules ? [ "ath9k_htc" ]

, sysfs-base-glob ? "/sys/bus/pci/drivers/mwifiex_pcie/????:??:??.?"
#, sysfs-base-glob ? "/sys/bus/usb/drivers/ath9k_htc/*-*:*.*"

# FIXME: make it clear that this directory contains secrets and must persist
# across reboots
, state_directory ? throw "missing state_directory"
, conf_directory ? throw "missing conf_directory"
}:
let delete-all-interfaces = ''
# delete any preexisting mac interfaces
${pkgs.findutils}/bin/find $SYSFS_BASE/net/ \
     -mindepth 1 \
     -maxdepth 1 \
     -type d \
     -execdir basename {} \; \
  2>/dev/null \
| ${pkgs.findutils}/bin/xargs -I{} iw dev {} del \
2>/dev/null
'';
in
(six.mkFunnel {
  passthru.after = [ targets.global.coldplug ];
  run = pkgs.writeScript "run"
(''
#!${pkgs.runtimeShell}
exec 2>&1

${lib.concatStringsSep "\n" (lib.map (m: "${pkgs.kmod}/bin/modprobe ${m} || exec sleep 5") modules)}
if [ -e ${sysfs-base-glob} ]; then
  true
else
  echo '${sysfs-base-glob}' does not exist yet, sleeping...
  exec sleep 5
fi
SYSFS_BASE=$(readlink -f ${sysfs-base-glob})

# find the phy, set its name
${pkgs.iw}/bin/iw phy $(cat $SYSFS_BASE/ieee80211/*/name) set name ${phyname} || exit -1
${pkgs.iw}/bin/iw phy ${phyname} set antenna all
#${pkgs.iw}/bin/iw phy ${phyname} set txpower <auto|fixed|limit> <tx power in mBm>

${delete-all-interfaces}

# create the mac interface; can suffix this with `addr $MAC_ADDR` if desired
${pkgs.iw}/bin/iw phy ${phyname} interface add ${ifname} type managed

# STATE_DIRECTORY= is where it looks for the networks files (i.e. /run)
export STATE_DIRECTORY=${state_directory}

# where to look for main.conf
export CONFIGURATION_DIRECTORY=${conf_directory}

#export IWD_RTNL_DEBUG=1
#export IWD_GENL_DEBUG=1  # "enables printing Generic Netlink communication with the kernel"
#export IWD_DHCP_DEBUG=1
export IWD_DHCP_DEBUG=debug   # debug info warn error
export IWD_TLS_DEBUG=1
export IWD_WSC_DEBUG_KEYS=1

# TODO: signal readiness?

exec ${pkgs.eiwd}/libexec/iwd --interfaces ${ifname}
'');
  finish = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    ${delete-all-interfaces}
    exit 0
  '';
})
