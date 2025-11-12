{
  lib,
  yants,
  extra-by-name-dirs,
  infuse,
  sixos,
  ...
}:
let

  host-stages = [
    # build the ifconns and interfaces attributes
    (
      (final: prev:
        let
          ifconns =
            # all the subnets to which it is directly attached.
            lib.pipe final.site.subnets [
              (
                lib.mapAttrs (subnetName: subnet:
                  lib.pipe subnet [
                    # drop the __netmask key, which is not a host
                    (lib.filterAttrs (hostName: _:
                      !(lib.strings.hasPrefix "__" hostName)
                    ))

                    # add ${host}.netmask
                    (lib.mapAttrs
                      (hostName: ifconn: {
                        netmask = subnet.__netmask;
                      } // ifconn))
                  ])
              )
              (lib.mapAttrsToList
                (subnetName: subnet:
                  if subnet?${prev.name}
                  then lib.nameValuePair subnetName subnet.${prev.name}
                  else null))
              (lib.filter (v: v!=null))
              lib.listToAttrs
            ];
        in prev // {
          inherit ifconns;
          interfaces =
            { lo.type = "loopback"; } //
            lib.pipe ifconns [
              (lib.mapAttrsToList
                (subnetName: ifconn:
                  if ifconn?ifname
                  then lib.nameValuePair ifconn.ifname ({
                    subnet = subnetName;
                  } // lib.optionalAttrs (final.site.subnets.${subnetName}?__type) {
                    type = final.site.subnets.${subnetName}.__type;
                  })
                  else null))
              (lib.filter (v: v!=null))
              lib.listToAttrs
            ];
        }
      ))

    # default kernel setup
    (
      (final: prev:
        let
          mkKernelConsoleBootArg =
            { device
            , baud ? null }:
            "console=${device}"
            + lib.optionalString (baud!=null) ",${toString baud}";
        in infuse prev {
          boot.kernel.params   = _: [
            "root=${final.boot.rootfs.parameter}"
          ] ++ lib.optionals final.boot.rootfs.first-mount-is-readonly [
            "ro"
          ] ++ lib.optionals (final.boot?kernel.console) [
            (mkKernelConsoleBootArg final.boot.kernel.console)
          ];
          boot.kernel.modules  = _: "${final.boot.kernel.package}";
          boot.kernel.package  = _: final.pkgs.callPackage sixos.mkHost.kernel { };
          boot.rootfs.label.__assign = "root";
          boot.rootfs.parameter.__assign = "LABEL=${final.boot.rootfs.label}";
          boot.rootfs.first-mount-is-readonly.__assign = true;

          # If the bootloader or its configuration is stored on a mountable
          # filesystem, this should be set to that filesystem's LABEL.  Mainly
          # used for uboot.
          boot.loader.filesystem.label.__assign = "boot";
        }
      ))

    # arch stage is allowed to alter the tags
    (
      (final: prev: infuse prev
        ({
          x86_64-unknown-linux-gnu =
            import ./arch/amd64 {
              inherit final infuse;
            };
          mips64el-unknown-linux-gnuabi64 =
            import ./arch/mips64 {
              inherit final infuse;
            };
          powerpc64le-unknown-linux-gnu =
            import ./arch/powerpc64 {
              inherit final infuse;
            };
          aarch64-unknown-linux-gnu =
            import ./arch/arm64 {
              inherit lib final infuse;
            };
          mips-unknown-linux-gnu =
            import ./arch/mips32 {
              inherit lib final infuse;
            };
          armv7l-unknown-linux-gnueabi =
            import ./arch/arm32 {
              inherit lib final infuse;
            };
          "" = {};
        }.${prev.canonical or ""})  # FIXME: use final.canonical
      ))

  ] ++ sixos.mkHost.initrd;
in
host-stages
