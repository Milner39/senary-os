{ lib
, infuse
, six-initrd
, sixos
, ...
}:

[(final: prev: infuse prev {
  boot.initrd.ttys.__default = {};
  boot.initrd.insmod.__default = [];
  boot.initrd.image.__init =
    (six-initrd {
      inherit lib;
      inherit (final) pkgs;
    })
      .minimal.override {
        contents = final.boot.initrd.contents // {
          # ensure that early/fail cannot "fall through" -- exec a shell instead
          "early/fail" = (final.boot.initrd.contents."early/fail" or []) ++ [''
            exec /bin/sh
          ''];
        };
      };

  boot.initrd.contents."early/run".__init = [''
    modprobe btrfs || true # not sure why this is necessary
    modprobe ext4 || true  # sterling has rootfs as ext4
    ${lib.concatStrings (lib.map (module: ''
      modprobe ${module}
    '') final.boot.initrd.insmod)}
    sleep 5  # yuck
  ''];

  # FIXME: need this in the rootfs as well
  boot.initrd.contents."etc/modprobe.conf".__init =
    builtins.toFile "modprobe.conf"
      (lib.pipe final.boot.kernel.modules-blacklist [
        (lib.map (module: "blacklist ${module}\n"))
        lib.concatStrings
      ]);

  # FIXME: leverage module-names and makeModulesClosure here
  boot.initrd.contents."lib/modules".__init = "${final.boot.kernel.modules}/lib/modules/";

})]
