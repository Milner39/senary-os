{ lib
, infuse
, ...
}:

final: prev: infuse prev {
  boot.loader.update.__assign = let
    inherit (final) pkgs;
  in pkgs.writeShellScript "update-syslinux" ''
    ${pkgs.busybox}/bin/busybox blkid | ${pkgs.busybox}/bin/busybox grep -q 'LABEL="${final.boot.rootfs.label}"' || \
      (echo -e '\n***\nno device with LABEL=${final.boot.rootfs.label}, refusing to update bootloader (sanity check)\n***\n'; exit -1)
    ${pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint
    ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint 2>/dev/null || true # in case it was mounted
    ${pkgs.busybox}/bin/mount LABEL=${final.boot.loader.filesystem.label} /run/six/update-bootloader-mountpoint
    ${pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint/{normal,fallback}
    ${pkgs.busybox}/bin/cp -L $1/boot/kernel /run/six/update-bootloader-mountpoint/normal/kernel
    ${pkgs.busybox}/bin/cp -L $1/boot.initrd.image /run/six/update-bootloader-mountpoint/normal/initrd
    ${pkgs.busybox}/bin/cp -L $2/boot/kernel /run/six/update-bootloader-mountpoint/fallback/kernel
    ${pkgs.busybox}/bin/cp -L $2/boot.initrd.image /run/six/update-bootloader-mountpoint/fallback/initrd
    ${pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint/boot/syslinux
    cat > /run/six/update-bootloader-mountpoint/boot/syslinux/syslinux.cfg <<EOF
    DEFAULT sixos-normal

    MENU TITLE ------------------------------------------------------------
    TIMEOUT 50

    LABEL sixos-normal
      MENU LABEL sixos
      LINUX /normal/kernel
      INITRD /normal/initrd
      APPEND $(cat $1/boot/kernel-params)

    LABEL sixos-fallback
      MENU LABEL sixos (fallback to last successful boot)
      LINUX /fallback/kernel
      INITRD /fallback/initrd
      APPEND $(cat $2/boot/kernel-params)
    EOF
    ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint
  '';
}
