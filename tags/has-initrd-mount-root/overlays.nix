{ lib
, infuse
, ... }:

[(host-final: prev: infuse prev ({

  boot.initrd.image.__input.contents."early/run".__append =
    host-final.boot.initrd.mount-root;

  #
  # Mountpoints for /dev /sys /run and /proc must exist before we switch_root to
  # an s6-linux-init-based root filesystem.  If they don't exist (typically on
  # the very first boot after a new install), we take the path of least evil and
  # try to create them by remounting read-write.
  #
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
}))]
