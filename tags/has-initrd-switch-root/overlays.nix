{ lib
, infuse
, ... }:

# switch_root into the chosen profile
[(final: prev: infuse prev ({
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
}))]
