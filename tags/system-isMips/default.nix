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
})
