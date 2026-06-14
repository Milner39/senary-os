{ lib
, infuse
, ...
}:

# FIXME: I don't think grub-boot is respecting boot.kernel.params

# TODO: make sure I am getting hardware accelerated video
# TODO: pkgs.mesa-asahi-edge is the experimental GPU driver

# TODO: pkgs.speakersafetyd isn't working
# TODO: headphone jack is set to zero volume at boot; need to `amixer -c 0 set "Jack DAC" 100%`

# TODO: Figure out some kind of video-out for traveling

# TODO: consider usb booting from a stick as a way to ensure immutability?
# TODO: uboot bootmenu?

# TODO: gccarch.__assign = "??";

# TODO: fix perhipheral firmware extractor situation

# Commits to consider (up to 9fe29a63b23005acfcd1324a9e78b6241226cdb1):
#  - dc41204032429d2bc93fabe5f4f407b0e4b31bf8 speaker volume
#  - 24ab28e47b586f741910b3a2f0428f3523a0fff3 upstream m1n1
#  - 357304e976a2be1d6cfc9b9bedf8e77eea16933f boot logo
#  - 2e365dec65d18bf1e0aec823788a9604b2a26326 possible gpu driver crashes
#  - fbe970a2b9b65425d9fb98882c0ad12d1b466390 proxyclient

[
(final: prev:

let
  nixos-apple-silicon-support = builtins.fetchGit {
    url = "https://github.com/nix-community/nixos-apple-silicon";
    #rev = "85502eb9b2fe860eaa5357050928f41fe9cba6ea";   # NixOS install
    rev = "417278ff258f4111a24a3534f4250fcf74aca44a";    # sixos, right before de-vendorizing the kernel .config
    #rev = "4c57821ede670f788a9d3fabfd70cd7f09df696d";   # last Nixpkgs 25.11
  };

  pkgs-asahi = final.pkgs // {
    linux-asahi =
      (final.pkgs.callPackage "${nixos-apple-silicon-support}/apple-silicon-support/packages/linux-asahi" {
      });
  };

  # This doesn't work
  peripheral-firmware =
    let
      config = {
        hardware.asahi.enable = true;
        hardware.asahi.pkgs = pkgs-asahi;
        hardware.asahi.extractPeripheralFirmware = true;
        #hardware.asahi.peripheralFirmwarePath =
      };
    in pkgs-asahi.stdenv.mkDerivation {
      name = "asahi-peripheral-firmware";
      nativeBuildInputs = [ pkgs-asahi.asahi-fwextract pkgs-asahi.cpio ];
      buildCommand = ''
        mkdir extracted
        mkdir tarball
        ln -s ${config.hardware.asahi.peripheralFirmwarePath} tarball/all_firmware.tar.gz
        asahi-fwextract tarball extracted
        mkdir -p $out/lib/firmware
        cat extracted/firmware.cpio | cpio -id --quiet --no-absolute-filenames
        mv vendorfw/* $out/lib/firmware
      '';
    };

  nixos-asahi-kernel =
    (import "${nixos-apple-silicon-support}/apple-silicon-support/modules/kernel" {
      inherit lib;
      config = {
        boot.kernelPatches = [
          {
            # busybox modprobe does not understand zstd-compressed modules
            name = "Compress modules with XZ, not ZSTD";
            patch = null;
            extraConfig = ''
              MODULE_COMPRESS y
              MODULE_COMPRESS_XZ y
              MODULE_COMPRESS_ZSTD n
              FW_LOADER_COMPRESS_XZ y
              FW_LOADER_COMPRESS_ZSTD n
            '';
          }
        ];
        hardware.asahi.enable = true;
        hardware.asahi.pkgs = pkgs-asahi;
      };
      pkgs = pkgs-asahi;
    }).config.content;

in
infuse prev {

  # pre-userspace serial console
  #boot.kernel.console.device.__assign = "ttySAC0";
  #boot.kernel.console.baud.__assign = 115200;

  # userspace serial console
  #boot.initrd.ttys.ttySAC0.__assign = 115200;

  boot.kernel.params.__append = [
    "earlycon"

    # FIXME: this is important enought that it should be compiled-in to the
    # kernel image.
    #
    # Scary comment copied from nixos-apple-silicon:
    #
    # Apple's SSDs are slow (~dozens of ms) at processing flush requests which
    # slows down programs that make a lot of fsync calls. This parameter sets
    # a delay in ms before actually flushing so that such requests can be
    # coalesced. Be warned that increasing this parameter above zero (default
    # is 1000) has the potential, though admittedly unlikely, risk of
    # UNBOUNDED data corruption in case of power loss!!!! Don't even think
    # about it on desktops!!
    "nvme_apple.flush_interval=0"
  ];

  boot.initrd.insmod.__append =
    nixos-asahi-kernel.boot.initrd.availableKernelModules;

  boot.kernel.package.__assign =
    nixos-asahi-kernel.boot.kernelPackages.kernel;

  boot.kernel.firmware.__append = [
    (final.pkgs.runCommand "asahi-peripheral-firmware" {} ''
      mkdir $out
      cd $out
      tar xvzf ${../../../site/misc/asahi/asahi-peripheral-firmware.tar.gz}
    '')
  ];

  # recommended by nixos-apple-silicon
  targets.cpufreq.__input.governor.__default = "schedutil";

  targets.speakersafetyd.__init = final.services.speakersafetyd { };
})

]

