{ lib
, yants
, infuse
, ...
}:

{

implies = {
  has-hwclock = true;
};

__functor = _:

final: prev: infuse prev ({

  boot.kernel.package.__input.structuredExtraConfig = {
    CRYPTO_AES_GCM_P10.__assign  = "n";
    CRYPTO_CHACHA20_P10.__assign = "n";
    CRYPTO_POLY1305_P10.__assign = "n";

    DRM_AMDGPU.__assign = "m";
    NUMA_BALANCING.__assign = "y";
    NUMA_BALANCING_DEFAULT_ENABLED.__assign = "y";
  };

  boot.initrd.ttys.__assign = { hvc0 = 115200; };
  boot.kernel.console.device = _: "hvc0";
  boot.kernel.console.baud.__assign = 115200;
  boot.kernel.payload = _: "${final.boot.kernel.package}/vmlinux";
  boot.kernel.image.__assign = "${final.boot.kernel.package}/vmlinux";

});

}
