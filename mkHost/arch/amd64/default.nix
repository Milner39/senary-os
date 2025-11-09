{ final
, ...
}:

{
  boot.kernel.payload.__assign = "${final.boot.kernel.package}/bzImage";
  boot.kernel.image.__assign   = "${final.boot.kernel.package}/vmlinux";
}
