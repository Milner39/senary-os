{ lib
, infuse
, ...
}:

# TODO: identify "scratch drives" using the partition table uuid:
#   grep -lxF eui.002538db11418915 /sys/block/* /wwid
#   sfdisk --disk-id /dev/nvme0n1 33333333-3333-3333-3333-333333333333
final: prev: infuse prev {
  boot.initrd.insmod.__append = lib.optionals final.tags.is-kgpe [
    "e1000e"
  ] ++ lib.optionals final.tags.is-rockpi4 [
    "dwmac_rk"
  ];
}
