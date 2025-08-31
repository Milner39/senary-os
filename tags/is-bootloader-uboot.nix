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
    let
      inherit (final) pkgs;
      # FIXME: make this configurable
      root-device-label = "root";
      boot-device-label = "boot";
    in
    pkgs.writeShellScript "update-bootloader" ''
      ${pkgs.busybox}/bin/busybox blkid | ${pkgs.busybox}/bin/busybox grep -q 'LABEL="${root-device-label}"' || \
        (echo -e '\n***\nno device with LABEL=${root-device-label}, refusing to update bootloader (sanity check)\n***\n'; exit -1)
      ${pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint
      ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint 2>/dev/null || true # in case it was mounted
      ${pkgs.busybox}/bin/mount LABEL=${boot-device-label} /run/six/update-bootloader-mountpoint
      ${pkgs.busybox}/bin/cp -L $2/boot/kernel         /run/six/update-bootloader-mountpoint/fallback.uImage
      ${pkgs.busybox}/bin/echo -n bootargs=         >  /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${pkgs.busybox}/bin/cat $2/boot/kernel-params >> /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${pkgs.busybox}/bin/echo                      >> /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${pkgs.busybox}/bin/cp -L $1/boot/kernel         /run/six/update-bootloader-mountpoint/normal.uImage
      ${pkgs.busybox}/bin/echo -n bootargs=         >  /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${pkgs.busybox}/bin/cat $1/boot/kernel-params >> /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${pkgs.busybox}/bin/echo                      >> /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint
    '';
}
