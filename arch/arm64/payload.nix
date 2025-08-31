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
, preload-hex     # this is where the tftp image is copied to
, loadaddr-hex    # where the kernel is located when we jump to it
, initrd-addr-hex # where the initrd is located
, fdtaddr-hex     # where the devicetree is located when we jump to the kernl
, initrd-compression ? "none"
, uboot-commands  ? null
, append-dtb-to-kernel ? false
}:

assert append-dtb-to-kernel -> dtb!=null;
assert linux-command-line != null -> dtb != null;

stdenv.mkDerivation {
  pname = "kernel${lib.optionalString (initrd!=null) "+initrd"}${lib.optionalString (dtb!=null) "+dtb"}";
  inherit (kernel.package) version;
  dontUnpack = true;
  nativeBuildInputs = [
    dtc bc
  ];

  buildPhase = (lib.optionalString (dtb != null) (''
    cp ${dtb} dtb
    chmod u+w dtb
    dtc -I dtb -O dts dtb -o before.dts
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
    ${buildPackages.ubootTools}/bin/mkimage \
      -D "-I dts -O dtb -p 4096" \
      -B 1000 \
      -f dts \
      uImage
    mv uImage $out/uImage
    runHook postInstall
  '';
}
