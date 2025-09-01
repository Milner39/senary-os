{ final
, name
, infuse
, pkgs ? final.pkgs
, lib /*? pkgs.lib*/          # no default in order to prevent infinite recursion
}:

{
  boot.kernel.image.__assign = "${final.boot.kernel.package}/Image";
  boot.kernel.payload = prev:
    if !final.tags.is-bootloader-uboot
    then prev
    else let
      preload-hex     =  "9800800";
      loadaddr-hex    =  "6000000";
      initrd-addr-hex =  "2080000";
      fdtaddr-hex     =  "1f00000";
      uboot-commands  = [
        "fatload mmc 0 ${loadaddr-hex} normal.uImage"
        "fdt addr ${loadaddr-hex}"
        "fdt get value bootscript /images/script data"
        "run bootscript"
      ];
    in
      pkgs.callPackage ../uboot ({
        inherit (final.boot) kernel;
        inherit preload-hex    ;
        inherit loadaddr-hex   ;
        inherit initrd-addr-hex;
        inherit fdtaddr-hex    ;
        inherit uboot-commands;
        initrd = final.boot.initrd.image;
        params = final.boot.kernel.params;
        arch = "arm64";
        initrd-compression = "gzip";
    } // lib.optionalAttrs (final?boot.kernel.dtb) {
      dtb    = final.boot.kernel.dtb;
    } // lib.optionalAttrs (final?boot.loader.uboot-commands) {
      inherit (final.boot.loader) uboot-commands;
    });
}
