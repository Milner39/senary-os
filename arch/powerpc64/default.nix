{ final
, name
, infuse
, pkgs ? final.pkgs
, lib ? pkgs.lib
}:

{
  boot.initrd.ttys.hvc0 = _: 115200;
  boot.kernel.console.device = _: "hvc0";
  boot.kernel.console.baud.__assign = 115200;
  boot.kernel.payload = _: "${final.boot.kernel.package}/vmlinux";
  boot.kernel.image.__assign = "${final.boot.kernel.package}/vmlinux";

  tags.is-bootloader-petitboot.__assign = true;
}
