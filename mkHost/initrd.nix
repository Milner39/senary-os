{ lib
, infuse
, six-initrd
, sixos
, ...
}:

let

  # basic minimal initrd
  basic-initrd =
    (final: prev: infuse prev {
      boot.initrd.insmod.__init = [];
      boot.initrd.image.__assign =
       (six-initrd {
         inherit lib;
         inherit (final) pkgs;
       })
         .minimal.override {
           contents = final.boot.initrd.contents;
         };
  });

  # abduco-enabled initrd
  abduco =
  (final: prev: infuse prev ({
    boot.initrd.contents =
      lib.mapAttrs
        (_: val: { __default = val; })
        ((six-initrd {
          inherit lib;
          inherit (final) pkgs;
        }).abduco {
          ttys = final.boot.initrd.ttys;
        });
  }));

  # minimum necessary contents
  minimal-contents =
  (final: prev: let
    inherit (final) pkgs;
  in infuse prev ({
    boot.initrd.image.__input.compress = _: "gzip";
    boot.initrd.image.__input.contents = ({
      "early/run".__append = [''
        modprobe btrfs || true # not sure why this is necessary
        modprobe ext4 || true  # sterling has rootfs as ext4
      ''] ++ [(
        lib.concatStrings (lib.map (module: ''
          modprobe ${module}
        '') final.boot.initrd.insmod)
      )] ++ [''
        sleep 5  # yuck
      ''];
      "early/fail".__append = [''
        exec /bin/sh

      ''];
    } // lib.optionalAttrs (!final.pkgs.stdenv.hostPlatform.isMips64) {
      # FIXME: leverage module-names and makeModulesClosure here
      "lib/modules"     = _: "${final.boot.kernel.modules}/lib/modules/";

    } // lib.optionalAttrs (final.boot.kernel?modules-blacklist) {
      # FIXME: need this in the rootfs as well
      "etc/modprobe.conf".__assign =
        builtins.toFile "modprobe.conf"
          (lib.pipe final.boot.kernel.modules-blacklist [
            (lib.map (module: "blacklist ${module}\n"))
            lib.concatStrings
          ]);
    });
  }));

  # cryptsetup-enabled initrd
  cryptsetup-initrd =
  (final: prev: let inherit (final) pkgs; in infuse prev ({
    boot.initrd.image.__input.contents = lib.optionalAttrs (!final.tags.is-nfsroot) {
      # FIXME: at nextboot-time, verify that there is a luks volume with the label `boot`
      "early/run".__append = [''
        for DEV in $(blkid | grep 'TYPE="crypto_LUKS"' | sed 's_^\([^\:]*\):.*$_\1_;t;d'); do
            # we're relying here on the fact that the keyfile passed by the
            # pre-kexec initrd will only work on one of the volumes...
            if cryptsetup luksDump $DEV | grep -q '^Label:\W*\(boot\|rescue\)$'; then
                cryptsetup luksOpen --key-file /miniboot-cryptsetup-keyfile $DEV miniboot-root
            fi
        done
      ''];
      "sbin/cryptsetup" = _: let
        cryptsetup =
          infuse pkgs.pkgsStatic.cryptsetup ({
            __input.lvm2 = _: pkgs.pkgsStatic.lvm2;
            __input.withInternalArgon2 = _: true;
            __output.configureFlags.__append = [
              "--disable-external-tokens"
              "--disable-ssh-token"
              "--disable-luks2-reencryption"
              "--disable-veritysetup"
              "--disable-integritysetup"
              "--disable-selinux"
              "--disable-udev"
              "--enable-internal-sse-argon2"
              "--with-crypto_backend=kernel"    # huge reduction: 4.4M to under 1M
            ];
          });
        in "${lib.getBin cryptsetup}/bin/cryptsetup";
    };
  }));

  # lvm-enabled initrd
  lvm-initrd =
  (final: prev: let inherit (final) pkgs; in infuse prev ( {
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
  }));

  mount-root =
  (host-final: prev: infuse prev ({
    boot.initrd.image.__input.contents."early/run".__append =
      host-final.boot.initrd.mount-root;
  }));

  #
  # Mountpoints for /dev /sys /run and /proc must exist before we switch_root to
  # an s6-linux-init-based root filesystem.  If they don't exist (typically on
  # the very first boot after a new install), we take the path of least evil and
  # try to create them by remounting read-write.
  #
  ensure-mountpoints =
  (final: prev: let
    inherit (final) pkgs;
  in infuse prev ({
    boot.initrd.contents."early/finish".__append = [''
      if ! (test -e /root/dev && test -e /root/sys && test -e /root/run && test -e /root/proc); then
        echo "root filesystem is missing one or more of /{dev,sys,run,proc}; remounting read-write to create them..."
        set -x
        mount -o remount,rw /root
        mkdir -m 0000 -p /root/dev
        mkdir -m 0000 -p /root/run
        mkdir -m 0000 -p /root/sys
        mkdir -m 0000 -p /root/proc
        mount -o remount,ro /root
        set +x
      fi
    ''];
  }));

  # switch_root into the chosen profile
  switch-root =
  (final: prev: let
    inherit (final) pkgs;
  in infuse prev ({
    boot.initrd.contents."early/finish".__append = [''
      CONFIGURATION=/nix/var/nix/profiles/nextboot
      set -- $(cat /proc/cmdline)
      for x in "$@"; do
          case "$x" in
              configuration=*)
              CONFIGURATION="''${x#configuration=}"
              ;;
          esac
      done
      echo
      echo initrd: will now switch_root to configuration $CONFIGURATION
      echo
      # sanity check: make sure that $CONFIGURATION exists
      (test -e /root$CONFIGURATION || test -L /root/$CONFIGURATION) \
        && exec switch_root /root $CONFIGURATION/boot/init
      exec /bin/sh
    ''];
  }));

in [
  basic-initrd
  abduco
  minimal-contents
  cryptsetup-initrd
  lvm-initrd
  mount-root
  ensure-mountpoints
  switch-root
]
