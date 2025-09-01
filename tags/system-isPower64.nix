{ lib
, yants
, infuse
, ...
}:

final: prev: infuse prev ({

  # powerpc workstations generally have battery-backed hardware clocks
  tags.has-hwclock.__default = true;

  boot.kernel.package.__input.structuredExtraConfig = {
    CRYPTO_AES_GCM_P10.__assign  = "n";
    CRYPTO_CHACHA20_P10.__assign = "n";
    CRYPTO_POLY1305_P10.__assign = "n";
  };
})
