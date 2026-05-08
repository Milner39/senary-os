{ lib
, infuse
, ... }:

[(final: prev: let inherit (final) pkgs; in infuse prev ( {
    boot.initrd.image.__input.contents = lib.optionalAttrs (!final.tags.is-nfsroot && !final.tags.dont-mount-root) {
      # FIXME: at nextboot-time, verify that there is an lvm volume with the @boot tag
      "early/run".__append = [''
        # lvm lvchange --addtag @boot vg/lv
        /sbin/lvm lvchange -a ay @boot
        mkdir -p /root
      ''];
      "sbin/dmsetup"    = _: "${lib.getBin pkgs.pkgsStatic.lvm2}/bin/dmsetup.static";
      "sbin/lvm"        = _: "${lib.getBin pkgs.pkgsStatic.lvm2}/bin/lvm";
    };

    # We try first with `-o degraded` to acommodate booting from btrfs raid1
    # where only one of the volumes was decrypted
    boot.initrd.mount-root.__default = [''
      mount -o ro,degraded LABEL=boot /root || \
      mount -o ro          LABEL=boot /root || \
      exit 1
    ''];
  }))]
