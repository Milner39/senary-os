
#
# TODO(amjoseph): a bunch of this is only applicable to Octeons, not to all
# MIPSen.
#
# TODO(amjoseph): attempt to check the "setup requirements" programmatically
# instead of expecting people to read this file.
#

/*

IMPORTANT SETUP REQUIREMENTS!

You must execute the following commands from the uboot prompt (on the serial
console) before attempting to boot sixos on an octeon router.  I recommend:

1. Boot from recovery media (any distro with the `nix` binary)
2. Copy your configuration into the store
3. Run `${configuration}/bin/nextboot`
4. Reboot while pressing "enter" on the serial console to enter the uboot prompt
5. Paste the commands below
   - the (hexadecimal) value `20000000` below should match the `loadaddr-hex` parameter
   - the `numcores` value should be `4` for the ER-4 and ER-6
6. Type `reset`

```
env default -a
setenv bootcmd  'run normal'
setenv bootargs ''
setenv loadaddr 20000000
setenv numcores 4
setenv normal   'fatload mmc 0 $(loadaddr) normal.ubootenv; env import $(loadaddr) $(filesize); fatload mmc 0 $(loadaddr) normal.uImage; env run boot'
setenv fallback 'fatload mmc 0 $(loadaddr) fallback.ubootenv; env import $(loadaddr) $(filesize); fatload mmc 0 $(loadaddr) fallback.uImage; env run boot'
setenv usb      'usb start; fatload usb 0 $(loadaddr) normal.ubootenv; env import $(loadaddr) $(filesize); fatload usb 0 $(loadaddr) normal.uImage; env run boot'
setenv boot     'fdt addr $(loadaddr); fdt get value bootscript /images/script data; run bootscript'
saveenv
reset
```

You'll also need to make sure that `/dev/mmcblk0p1` is a partition of type
`vfat` (the routers ship this way from the manufacturer) with its partition
label set to `boot` (the routers do NOT ship this way).  To set the partition
label, use the `fatlabel` command from `dosfstools`:

```
fatlabel /dev/mmcblk0p1 boot
```

It has to be this exact partition because the uboot `bootcmd` above looks for
the first (zeroth) partition on the (only) mmc device.  Sixos uses volume labels
to find the partition.  You can use a different partition by adjusting the
`setenv bootcmd` above.

In theory it should be possible to set the uboot parameters (which are stored in
mtd flash) programmatically from a booted Linux kernel, rather than having to
use the serial console to do it via uboot.  I never got this working; here's my
unfinished attempt:

```
# I never got this to work properly... (this goes in /etc/fw_env.config)
fw_env = ''
  # MTD device name       Device offset   Env. size       Flash sector size       Number of sectors
  /dev/mtd0               0x7fe000        0x2000          0x1000
'';

set-up-mtd = ''
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 boot0   ${toString (       0 *1024)}      ${toString (3072*1024)}
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 dummy   ${toString (    3072 *1024)}      ${toString (1024*1024)}
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 eeprom  ${toString (    4096 *1024)}      ${toString (  64*1024)}
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 spare   ${toString ((64+4096)*1024)}      ${toString (   0*1024)}
'';
```


Misc Notes:

- If using `bootoctlinux` (which we currently are not using), you must remove
  the factory-shipped `vmlinux.64.md5` from `/dev/mmcblk0p1` -- this is the only
  way to disable md5 checking.

Network boot stuff:

```
setenv tftp_server_ip <REPLACE_ME>
setenv hostname <REPLACE_ME>
setenv netbootcmd 'dhcp; tftp $(loadaddr) $(tftp_server_ip):$(hostname)/uImage; fdt addr $(loadaddr); fdt get value bootscript /images/script data; run bootscript'
```



Copypasta to create a USB boot image:

```
DEV=/dev/sda
BOOT=${DEV}1
ROOT=${DEV}2
CONFIGURATION=/nix/store/pmg6lf81hxydyripafgcpmwv1z7qinfb-six-system-hayden-unknown-nixpkgs-version

parted $DEV mklabel gpt

parted $DEV mkpart kernel 0% 50M
mkfs -t msdos ${BOOT}
mkdir -p /mnt/tmp
mount ${BOOT} /mnt/tmp
cp $(realpath $CONFIGURATION/boot/kernel) /mnt/tmp/normal.uImage
echo "bootargs=root=LABEL=boot ro console=ttyS0,115200 init=$CONFIGURATION/boot/init configuration=$CONFIGURATION" | tee -a /mnt/tmp/normal.ubootenv
umount /mnt/tmp
fatlabel ${BOOT} boot

parted $DEV mkpart root 50M 100%
mkfs -t btrfs ${ROOT}
mount -o noatime,compress=lzo ${ROOT} /mnt/tmp
nix --extra-experimental-features nix-command copy --to /mnt/tmp $CONFIGURATION

# FIXME: still need this because the initrd expects /run to be present
mkdir -p /mnt/tmp/run

# FIXME: still need this because s6-linux-init early PID1 expects sys,dev,proc to be present
mkdir -p /mnt/tmp/{sys,dev,proc}

btrfs fi label /mnt/tmp root
umount /mnt/tmp

eject ${DEV}
```



*/

{ final
, name
, infuse
, pkgs ? final.pkgs
, lib ? pkgs.lib

#
# For some utterly strange reason the kernel and initrd must both be
# placed within the 16mbyte window between 0.5gb and 0.5gb+16mbyte.
# Need to figure out why.
#
, preloadaddr-hex      ?   "22000000"  # where the uImage is placed when first loaded from network or disk
, fdtaddr-hex          ?      "80000"  # where the devicetree is located when we jump to the kernel
, loadaddr-hex         ?   "20000000"  # where the kernel is located when we jump to it
, initrd-alignment-hex ?      "10000"  # initrd address will be aligned to multiples of this
, initrd-addr-hex      ?   "20C90000"  # where the initrd is located
, initrd-ceiling-hex   ?   "21000000"  # build will fail if top of initrd is above this address
, initrd-compression   ? "gzip"

#
# Although the factory bootloader (u-boot) can be instructed to pass a DTB to
# the kernel, it mangles the DTB in the process (likely trying to helpfully
# autodetect something).  Ubiquiti ships big-endian kernels so maybe their
# bootloader assumes big-endian?  Anyways, if you want to use `vmlinux` kernel
# images instead of a FIT (Flattened Image Tree) archive you'll need to enable
# this.
#
, append-dtb-to-kernel ? false

, uboot-commands ? [
  "fdt move $(fileaddr) 0x${preloadaddr-hex}"
  "fdt addr 0x${preloadaddr-hex}"
  "usb start"
  "fdt header"
  "fdt get addr kernel_addr /images/kernel data"
  "fdt get value rd_start /images/ramdisk load"
  "imxtract 0x${preloadaddr-hex} ramdisk $(rd_start)"
  "fdt get size rd_size /images/ramdisk data"
  "bootm start 0x${preloadaddr-hex}"
  "bootm loados"
  "bootm fdt"
  "bootoctlinux $(kernel_addr) numcores=$(numcores) endbootargs rd_start=$(rd_start) rd_size=$(rd_size) ${lib.concatStringsSep " " final.boot.kernel.params} $(bootargs)"
]

}:

let

  payload = pkgs.callPackage ../uboot ({
    inherit (final.boot) kernel;
    initrd = final.boot.initrd.image;
    params = final.boot.kernel.params;
    preload-hex = preloadaddr-hex;
    arch = "mips";
    stdout-path = "soc/serial@1180000000800";
    inherit fdtaddr-hex;
    inherit loadaddr-hex;
    inherit initrd-alignment-hex;
    inherit initrd-addr-hex;
    inherit initrd-ceiling-hex;
    inherit uboot-commands;
  } // lib.optionalAttrs (final?boot.kernel.dtb) {
    dtb    = final.boot.kernel.dtb;
  } // lib.optionalAttrs (final?boot.loader.uboot-commands) {
    inherit (final.boot.loader) uboot-commands;
  });
in
{
  boot.kernel.payload  = _: "${payload}/uImage";
  boot.kernel.image.__assign = "${final.boot.kernel.package}/vmlinux-${final.boot.kernel.package.version}";

  boot.kernel.dtb = _:
    if final.tags.is-er6
    then "${final.boot.kernel.package}/dtbs/cavium-octeon/cn7130_ubnt_edgerouter_6p.dtb"
    else "${final.boot.kernel.package}/dtbs/cavium-octeon/cn7130_ubnt_edgerouter4.dtb";

  boot.initrd.ttys.ttyS0 = _: 115200;
  boot.kernel.console.device.__assign = "ttyS0";
  boot.kernel.console.baud.__assign   = 115200;

  # The Linux octeon MMC drivers seem to take a very long time to notice that
  # the device exists... like one or two full seconds after the
  # kernel-to-userspace handoff.  So we have to wait for the root device to
  # appear.
  boot.initrd.mount-root.__append = [''
    while ! (busybox blkid | busybox grep -q 'LABEL="${final.boot.rootfs.label}"'); do
      echo waiting for a device with 'LABEL="${final.boot.rootfs.label}"' to appear
      sleep 1
    done
    mount -o ro LABEL="${final.boot.rootfs.label}" /root || exit -1
  ''];

  # mips devices have very small disks
  delete-generations = _: "5d";

  tags.is-bootloader-uboot.__assign = true;

  # mips devices have really tiny internal mmc devices
  service-overlays.__append = [(final: prev: infuse prev {
    targets.mounts."".__input.options.__append = [ "compress=zstd" ];
  })];

}

