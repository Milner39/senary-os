{ final
, name
, infuse
, pkgs ? final.pkgs
, lib /*? pkgs.lib*/          # no default in order to prevent infinite recursion
, boot-device-label ? "boot"  # filesystem from which uboot will read the kernel and initrd
, root-device-label ? "root"  # root filesystem device (post-boot)
}:

{
  boot.kernel.payload = prev:
    if !final.tags.is-nfsroot then prev else
      pkgs.callPackage ./payload.nix {
        kernel = "${final.boot.kernel.package}/Image";
        initrd = final.boot.initrd.image;
        params = final.boot.kernel.params;
        dtb    = final.boot.kernel.dtb;
      };
}
