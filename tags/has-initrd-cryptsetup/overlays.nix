{ lib
, infuse
, ... }:

[(final: prev: infuse prev ({
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
          infuse final.pkgs.pkgsStatic.cryptsetup ({
            __input.lvm2 = _: final.pkgs.pkgsStatic.lvm2;
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
  }))]

