{ lib
, infuse
, ... }:

[(final: prev: infuse prev ({

    # The initrd will attempt to decrypt any LUKS container having any of these
    # labels (set using `luksConfig --label`).
    #
    # If you want to boot off of a separately-encrypted multidevice filesystem,
    # you can either include the labels of all the devices here, or set them all
    # to the same label.
    #
    boot.initrd.encrypted-root.labels.__default =
      throw "you must set boot.initrd.encrypted-root.labels in order for tags.has-initrd-cryptsetup to work correctly";

    # The initrd will attempt to decrypt the root volume with this as the
    # dmsetup-name for the decrypted volume.
    boot.initrd.encrypted-root.dmsetup-name.__default =
      "decrypted-by-initrd";

    # If set to non-null, this path within the initrd should contain a
    # cryptsetup keyfile used to decrypt the root volume.  If null, the user
    # will be prompted for a password.
    boot.initrd.encrypted-root.keyfile.__default = null;

    boot.initrd.image.__input.contents =
      # FIXME this tag should conflict with is-nfsroot...
      lib.optionalAttrs (!final.tags.is-nfsroot) {
      # FIXME: at nextboot-time, verify that there is a luks volume with the label `boot`
      "early/run".__append = [(''
        for DEV in $(blkid | grep 'TYPE="crypto_LUKS"' | sed 's_^\([^\:]*\):.*$_\1_;t;d'); do
            # we're relying here on the fact that the keyfile passed by the
            # pre-kexec initrd will only work on one of the volumes...
            if cryptsetup luksDump $DEV | grep -q '^Label:\W*\(${
              lib.concatStringsSep "\\|" final.boot.initrd.encrypted-root.labels
            }\)$'; then
                DMSETUPNAME=$(echo $DEV | sed s_.*/__)
                cryptsetup luksOpen ${
                  lib.optionalString (final.boot.initrd.encrypted-root.keyfile or null != null)
                    "--key-file ${final.boot.initrd.encrypted-root.keyfile}"
                } $DEV ${final.boot.initrd.encrypted-root.dmsetup-name}-$DMSETUPNAME
            fi
        done
      '')];
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

