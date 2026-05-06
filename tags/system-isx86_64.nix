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

  # FIXME
  boot.rootfs.parameter.__assign = "LABEL=boot";

  boot.kernel.payload.__assign = "${final.boot.kernel.package}/bzImage";
  boot.kernel.image.__assign   = "${final.boot.kernel.package}/vmlinux";

  boot.kernel.package.__input.structuredExtraConfig = lib.mapAttrs (_: v: { __assign = v; }) {
    X86_X32_ABI = "y";
    #X86_AMD_PSTATE = "y";
    #X86_AMD_PSTATE_UT = "m";
    #X86_BOOTPARAM_MEMORY_CORRUPTION_CHECK = "y";
    #X86_CPUID = "n";
    #X86_INTEL_MEMORY_PROTECTION_KEYS = "n";
    #X86_MCELOG_LEGACY = "y";     # /dev/mcelog
    #X86_MSR = "n";
    #X86_PCC_CPUFREQ = "y";

    GART_IOMMU = "y";
    NUMA_EMU = "y";
    #INTEL_IDLE = "y";

    DRM_AMDGPU = "m";
    NUMA_BALANCING = "y";
    NUMA_BALANCING_DEFAULT_ENABLED = "y";

    # need to compile these in for UAS to be compiled-in
    USB_STORAGE = "y";
    SCSI = "y";
  };
});

}
