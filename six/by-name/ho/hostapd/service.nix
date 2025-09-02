{ lib
, six
, pkgs
, targets
, yants
, interface
, ssid
, bridge ? null   # bridge interface (i.e. net.iface.xxx) to bridge the wireless interface to
, regulatory-domain-country-code ? "US"  # ISO/IEC 3166-1
, advertise-regulatory-domain-country-code ? regulatory-domain-country-code!=null
, radar-detection ? advertise-regulatory-domain-country-code
, mode
, enable-ht ? mode=="a" || mode=="g"
, enable-vht ? mode=="a"
, channel ? null # null means choose automatically
, wpa-passphrase
, ...
}:

let
  inherit (six.util) infuse;
  conf-file = pkgs.writeText "hostapd-conf"
    (import ./conf.nix {
      inherit lib;
      ifname = interface.ifname;
      bridge = bridge.ifname;
      inherit ssid;
      inherit regulatory-domain-country-code;
      inherit advertise-regulatory-domain-country-code;
      inherit radar-detection;
      inherit mode;
      inherit enable-ht;
      inherit enable-vht;
      inherit channel;
      inherit wpa-passphrase;
    });
in
six.mkFunnel {
  passthru.after = [
    targets.global.coldplug
    interface
  ] ++ lib.optionals (bridge != null) [
    bridge
  ];
  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    exec ${pkgs.hostapd}/bin/hostapd ${conf-file}
  '';
}

