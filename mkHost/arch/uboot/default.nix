{ lib
, stdenv
, dtc
, bc
, ubootTools
, buildLinux
, fetchpatch
, fetchurl
, runCommand
, callPackage
, buildPackages
, version ? "unknown-version"
, kernel ? throw "you must provide a kernel"
, initrd ? null
, dtb ? null
, arch
, params ? []
, linux-command-line ? null
, preload-hex                          # where the uImage is placed when first loaded from network or disk
, loadaddr-hex                         # where the kernel is located when we jump to it
, initrd-addr-hex                      # where the initrd is located
, fdtaddr-hex                          # where the devicetree is located when we jump to the kernel
, initrd-alignment-hex  ? null         # initrd address will be aligned to multiples of this
, initrd-ceiling-hex    ? null         # build will fail if top of initrd is above this address
, initrd-compression    ? "none"
, stdout-path           ? null

# These are the commands that uboot will execute after reading the payload from
# internal storage into RAM.  These commands are embedded into the payload.
, uboot-commands  ? null
, append-dtb-to-kernel ? false
}:

assert append-dtb-to-kernel -> dtb!=null;
assert linux-command-line != null -> dtb != null;
assert (initrd-ceiling-hex!=null) == (initrd-alignment-hex!=null);

stdenv.mkDerivation {
  pname = "kernel${lib.optionalString (initrd!=null) "+initrd"}${lib.optionalString (dtb!=null) "+dtb"}";
  inherit (kernel.package) version;
  dontUnpack = true;
  nativeBuildInputs = [
    dtc bc
  ];

  # Old buildPhase commands that are no longer needed (but might be useful
  # someday):
  #
  # fdtput    -p -v dtb -t x /chosen linux,initrd-start 0x${initrd-addr-hex}
  # fdtput    -p -v dtb -t x /chosen linux,initrd-end   0x$((echo 10k; wc -c < ${initrd}; echo 16o 16i; echo ${initrd-addr-hex}; echo '+f') | dc)
  # fdtput    -p -v dtb -t s /chosen bootargs           "rd_start=0x${initrd-addr-hex} rd_size=$(wc -c < ${initrd}) mem=0"
  # fdtput    -p -v dtb -t s /chosen bootargs           ${lib.escapeShellArg (lib.concatStringsSep " " params)}
  #
  buildPhase = (lib.optionalString (dtb != null) (''
    cp ${dtb} dtb
    chmod u+w dtb
    dtc -I dtb -O dts dtb -o before.dts

  '' + lib.optionalString (stdout-path != null) ''
    # not sure this matters
    fdtput    -p -v dtb -t s /chosen stdout-path   "${stdout-path}"

  '' + lib.optionalString (linux-command-line != null) ''
    fdtput -t s -v -p dtb /chosen bootargs ${lib.escapeShellArg linux-command-line}
  '' + ''
    dtc -I dtb -O dts dtb -o after.dts
  ''))
  #
  # kernel
  #
  + ''
    cp ${kernel.image} vmlinux
    chmod u+w vmlinux
  '' + lib.optionalString append-dtb-to-kernel ''
    $OBJCOPY --update-section \
      .appended_dtb=dtb \
      vmlinux
  ''
  #
  # initrd
  #
  + ''
    cp ${initrd} initrd
  '' + lib.optionalString (initrd-alignment-hex != null) ''
    chmod u+w initrd
    KERNEL_ADDR=$((0x${loadaddr-hex}))
    KERNEL_TOP=$(( 0x${loadaddr-hex} + $(cat vmlinux | wc -c) ))
    echo KERNEL_TOP is $(echo "10k16o $KERNEL_TOP f" | dc)
    KERNEL_TOP_PADDING=$(( ( 0x${initrd-alignment-hex} - ( $KERNEL_TOP % 0x${initrd-alignment-hex} ) ) 0x${initrd-alignment-hex}  ))
    echo KERNEL_TOP_PADDING is $(echo "10k16o $KERNEL_TOP_PADDING f" | dc)
    INITRD_ADDR=$(( $KERNEL_TOP + $KERNEL_TOP_PADDING ))
    echo INITRD_ADDR is $(echo "10k16o $INITRD_ADDR f" | dc)
    INITRD_TOP=$(( $INITRD_ADDR + $(cat initrd | wc -c) ))
    echo INITRD_TOP is $(echo "10k16o $INITRD_TOP f" | dc)
    if (( $INITRD_TOP > 0x${initrd-ceiling-hex} )); then
      echo kernel and initrd together do not fit beneath 0x${initrd-ceiling-hex}
      exit -1
    fi
  ''
  #
  # devicetree
  #
  + ''
    cat > dts <<EOF
    /dts-v1/;
    / {
        description = "kernel image with one or more FDT blobs";
        images {
            kernel {
                description = "kernel";
                data = /incbin/("vmlinux");
                type = "kernel_noload";
                arch = "${arch}";
                os = "linux";
                compression = "none";
                load = <0x${loadaddr-hex}>;
                entry = <0>;
                hash {
                    algo = "sha1";
                };
            };
  '' + lib.optionalString (initrd != null) ''
            ramdisk {
                description = "initramfs";
                data = /incbin/("initrd");
                type = "ramdisk";
                arch = "${arch}";
                os = "linux";
                compression = "${initrd-compression}";
                load = <0x${initrd-addr-hex}>;
                entry = <0>;
                hash {
                    algo = "sha1";
                };
            };
  '' + lib.optionalString (dtb != null) ''
            fdt {
                description = "fdt";
                data = /incbin/("dtb");
                type = "flat_dt";
                arch = "${arch}";
                compression = "none";
                load = <0x${fdtaddr-hex}>;
                hash {
                    algo = "sha1";
                };
            };
  '' + lib.optionalString (uboot-commands != null) ''
            script {
                description = "script";
                data = /incbin/("script");
                type = "script";
                compression = "none";
                hash {
                    algo = "sha1";
                };
            };
  '' + ''
        };
        configurations {
            default = "conf";
            conf {
                kernel = "kernel";
                fdt = "fdt";
                ramdisk = "ramdisk";
            };
        };
    };
    EOF
  ''
  #
  # boot script
  #
  + lib.optionalString (uboot-commands != null) ''
    echo ${lib.escapeShellArg
      (lib.concatStringsSep ";" uboot-commands)} > script
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    ln -s ${kernel.package}/{dtbs,lib,config-*,System.map-*} $out/

    ${buildPackages.ubootTools}/bin/mkimage \
      -D "-I dts -O dtb -p 4096" \
      -B 1000 \
      -f dts \
      uImage
    mv uImage $out/uImage

    cp ${kernel.image} $out/vmlinux
    chmod u+w $out/vmlinux
    cp ${initrd} $out/initrd

    runHook postInstall
  '';
}
