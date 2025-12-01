{ lib
, infuse
, ...
}:

final: prev: infuse prev {
  boot.initrd.insmod.__append = [
    "ehci_hcd"
    "ehci_pci"
    "sd_mod"
    "uas"
    "ahci"
  ];
}
