{ lib
, infuse
, six-initrd
, sixos
, ...
}:

# abduco-enabled initrd
[(final: prev: infuse prev {
  boot.initrd.contents =
    lib.mapAttrs
      (_: val: { __init = val; })
      ((six-initrd {
        inherit lib;
        inherit (final) pkgs;
      }).abduco {
        ttys =
          assert final.boot.initrd.ttys == {} -> throw "you must set boot.initrd.ttys";
          final.boot.initrd.ttys;
      });
})]
