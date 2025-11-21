{
  lib,
  yants,
  extra-by-name-dirs,
  infuse,
  types,
  sixos,
  ...
}:
let

  host-stages = host-overlays: [

    # initial host attrset
    (host-final: host-prev:
      host-prev // {
        inherit (host-prev) name;
        inherit (host-final) canonical;
        tags = types.default-tag-values;
      })

    # set system-isFooBar tags
    (host-final: host-prev:
      host-prev // {
        tags =
          types.set-tag-values (host-prev.tags //
            # This turns each of nixpkgs.lib's predicates "p" into an
            # attribute "system-${p}" whose value is a boolean
            # indicating whether or not the predicate matched this
            # host's `hostPlatform`.  These attribute names will be
            # intersected with those of site.tags, so if the site
            # doesn't declare a "system-${p}" tag that's okay.
            lib.flip lib.mapAttrs' lib.systems.inspect.predicates
              (predicate-name: predicate-function:
                let
                  system = lib.systems.parse.mkSystemFromString host-prev.canonical;
                  name = "system-${predicate-name}";
                  value = predicate-function system;
                in
                  lib.nameValuePair name value
              )
          );
      })

    # yuck, gross layering violation.  can't fix this until tags are allowed to
    # (monotonically) modify other tags.
    (host-final: host-prev:
      host-prev // {
        tags =
          host-prev.tags //
          lib.optionalAttrs host-prev.tags.system-isAarch64 {
            has-hwclock-fake = true;
            has-hwclock = false;
          } // lib.optionalAttrs host-prev.tags.system-isx86_64 {
            # x86 machines are required to have a battery-backed RTC
            has-hwclock-fake = false;
            has-hwclock = true;
          } // lib.optionalAttrs host-prev.tags.system-isMips64 {
            is-bootloader-uboot = true;
          } // lib.optionalAttrs host-prev.tags.system-isPower64 {
            # powerpc workstations generally have battery-backed hardware clocks
            has-hwclock = true;
            is-bootloader-petitboot = true;
          };
      })

    # build the ifconns and interfaces attributes
    (
      (host-final: host-prev:
        let
          ifconns =
            # all the subnets to which it is directly attached.
            lib.pipe host-final.site.subnets [
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
                  if subnet?${host-prev.name}
                  then lib.nameValuePair subnetName subnet.${host-prev.name}
                  else null))
              (lib.filter (v: v!=null))
              lib.listToAttrs
            ];
        in host-prev // {
          inherit ifconns;
          interfaces =
            { lo.type = "loopback"; } //
            lib.pipe ifconns [
              (lib.mapAttrsToList
                (subnetName: ifconn:
                  if ifconn?ifname
                  then lib.nameValuePair ifconn.ifname ({
                    subnet = subnetName;
                  } // lib.optionalAttrs (host-final.site.subnets.${subnetName}?__type) {
                    type = host-final.site.subnets.${subnetName}.__type;
                  })
                  else null))
              (lib.filter (v: v!=null))
              lib.listToAttrs
            ];
        }
      ))

    # default kernel setup
    (
      (host-final: host-prev:
        let
          mkKernelConsoleBootArg =
            { device
            , baud ? null }:
            "console=${device}"
            + lib.optionalString (baud!=null) ",${toString baud}";
        in infuse host-prev {
          boot.kernel.params   = _: [
            "root=${host-final.boot.rootfs.parameter}"
          ] ++ lib.optionals host-final.boot.rootfs.first-mount-is-readonly [
            "ro"
          ] ++ lib.optionals (host-final.boot?kernel.console) [
            (mkKernelConsoleBootArg host-final.boot.kernel.console)
          ];
          boot.kernel.modules  = _: "${host-final.boot.kernel.package}";
          boot.kernel.package  = _: host-final.pkgs.callPackage sixos.mkHost.kernel { };
          boot.rootfs.label.__assign = "root";
          boot.rootfs.parameter.__assign = "LABEL=${host-final.boot.rootfs.label}";
          boot.rootfs.first-mount-is-readonly.__assign = true;

          # If the bootloader or its configuration is stored on a mountable
          # filesystem, this should be set to that filesystem's LABEL.  Mainly
          # used for uboot.
          boot.loader.filesystem.label.__assign = "boot";

          boot.initrd.ttys.__default = { tty0 = null; };
          boot.initrd.contents.__default = { };
          boot.kernel.firmware.__default = [];
        }
      ))

    # apply host overlays from the site-dir
    (host-final: host-prev:
      host-prev //
      host-overlays.${host-prev.name}
        host-final
        host-prev)

  ] ++ sixos.mkHost.initrd ++ [

  ];
in
host-stages
