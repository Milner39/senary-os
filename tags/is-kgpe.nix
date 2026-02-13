{ lib
, infuse
, ...
}:

final: prev: infuse prev {

  gccarch.__assign = "bdver1";

  boot.initrd.insmod.__append = [
    "ehci_hcd"
    "ehci_pci"
    "sd_mod"
    "uas"
    "ahci"
  ];

  boot.kernel.package.__input.structuredExtraConfig = {
    MK8.__assign = "y";                   # CPU type
    SENSORS_K10TEMP.__assign = "m";
    SENSORS_W83795.__assign = "m";
    SENSORS_W83795_FANCTRL.__assign = "y";
    SENSORS_FAM15H_POWER.__assign = "m";
    W83627HF_WDT.__assign = "m";          # the "good watchdog"
    SP5100_TCO.__assign = "n";            # does not work and messes up iommu
    E1000E.__assign = "m";
  };

}
