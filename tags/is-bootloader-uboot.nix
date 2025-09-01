{ lib
, infuse
, ...
}:

final: prev: infuse prev {

  # TODO(amjoseph): get rid of `*.ubootenv` (it has serious shell-quoting
  # issues) and instead run `mkimage` from inside the `update-bootloader`
  # script.  We can't hardwire the configuration outpath into the `uImage`
  # because they're built by separate derivations and this would create a
  # reference cycle in `/nix/store`.  This will also clean up the install-media
  # situation.
  boot.loader.update.__assign =
    final.pkgs.writeShellScript "update-bootloader" ''
      ${final.pkgs.busybox}/bin/busybox blkid | ${final.pkgs.busybox}/bin/busybox grep -q 'LABEL="${final.boot.loader.filesystem.label}"' || \
        (echo -e '\n***\nno device with LABEL=${final.boot.loader.filesystem.label}, refusing to update bootloader (sanity check)\n***\n'; exit -1)
      ${final.pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint
      ${final.pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint 2>/dev/null || true # in case it was mounted
      ${final.pkgs.busybox}/bin/mount LABEL=${final.boot.loader.filesystem.label} /run/six/update-bootloader-mountpoint
      ${final.pkgs.busybox}/bin/cp -L $2/boot/kernel         /run/six/update-bootloader-mountpoint/fallback.uImage
      ${final.pkgs.busybox}/bin/echo -n bootargs=         >  /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${final.pkgs.busybox}/bin/cat $2/boot/kernel-params >> /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${final.pkgs.busybox}/bin/echo                      >> /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${final.pkgs.busybox}/bin/cp -L $1/boot/kernel         /run/six/update-bootloader-mountpoint/normal.uImage
      ${final.pkgs.busybox}/bin/echo -n bootargs=         >  /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${final.pkgs.busybox}/bin/cat $1/boot/kernel-params >> /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${final.pkgs.busybox}/bin/echo                      >> /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${final.pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint
    '';
}
