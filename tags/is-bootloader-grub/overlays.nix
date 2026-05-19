{ lib
, infuse
, ...
}:

[
  (final: prev: infuse prev {
    boot.loader.filesystem.spec.__default = null;
  })

  # TODO: add the ability to (optionally) copy the kernel and initrd to
  # specified paths on a specified device at update-bootloader time.
  #
  # Really, though, this logic ought to be shared with uboot and petitboot.

  (final: prev: infuse prev {
    boot.loader.update.__assign =
      if final.boot.loader.filesystem.spec == null
      then null
      else
    final.pkgs.writeShellScript "update-bootloader" ''
      ${final.pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint
      ${final.pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint 2>/dev/null || true # in case it was mounted
      ${final.pkgs.busybox}/bin/mount ${final.boot.loader.filesystem.spec} /run/six/update-bootloader-mountpoint || exit -1
      ${final.pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint/sixos/fallback
      ${final.pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint/sixos/normal
      ${final.pkgs.busybox}/bin/cp -L $2/boot/kernel         /run/six/update-bootloader-mountpoint/sixos/fallback/kernel
      ${final.pkgs.busybox}/bin/cp -L $2/boot/initrd         /run/six/update-bootloader-mountpoint/sixos/fallback/initrd
      ${final.pkgs.busybox}/bin/cp -L $1/boot/kernel         /run/six/update-bootloader-mountpoint/sixos/normal/kernel
      ${final.pkgs.busybox}/bin/cp -L $1/boot/initrd         /run/six/update-bootloader-mountpoint/sixos/normal/initrd
      ${final.pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint
    '';
})
]
