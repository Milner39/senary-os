{
  lib,
  yants,
  extra-by-name-dirs,
  infuse,
  types,
  sixos,
  ...
}:

#
# This file contains the single-host overlays that are applied *before* any of
# the site-specific overlays.
#

let

  init = final: prev:
    let
      autoArgs = {
        inherit lib six yants;
        inherit (final) pkgs targets services;
        host = final;
      };
      six = {
        mkService       = lib.callPackageWith autoArgs (import ../mkConfiguration/mkService.nix);
        mkBundle        = lib.callPackageWith autoArgs (import ../mkConfiguration/mkBundle.nix);
        mkOneshot       = lib.callPackageWith autoArgs (import ../mkConfiguration/mkOneshot.nix);
        mkFunnel        = lib.callPackageWith autoArgs (import ../mkConfiguration/mkFunnel.nix);
        mkLogger        = lib.callPackageWith autoArgs (import ../mkConfiguration/mkLogger.nix);
        util            = sixos.util { inherit (final) pkgs; };
        inherit (sixos) lib;
      };
    in
      prev // {

        # manually maintained, yuck
        gccarch = "";
        users = {};
        groups = {};
        boot = {};
        etc = {
          hosts = {};
        };
        doas-conf = [];
        extra-configuration-links = {};
        delete-generations = null;
        inherit (prev) name;
        inherit (final) canonical;
        tags = types.default-tag-values;

        # consider automatically allowing arguments `before` and `after` which, if
        # present, become `overrideAttrs` applied to `passthru`
        callService = service: lib.callPackageWith autoArgs service;
        callPackage = lib.callPackageWith autoArgs;

        inherit six;

        # A service is a Nix function which can be applied to various arguments,
        # like a callPackage in nixpkgs.  Each `src/by-name/??/${name}/service.nix`
        # defines one service.  See also `targets` below, which include service
        # *derivations*.
        services =
          (lib.flip builtins.mapAttrs sixos.by-name
            (name: service:
              final.callService service))
          // {

            # A logger which simply uses `cat` to send its stdin to the supervisor's
            # stdout, which is the same as the scanner's stdout.
            #
            # Unfortunately we need to create one of these (i.e. a separate s6-cat
            # process, plus a s6-supervise process for it) due to s6 restrictions:
            # every longrun either sends its stdout to some other longrun, or else
            # sends it to the catch-all logger (i.e. the console) -- and you cannot
            # change one type to the other without restarting the service.  In the
            # case of mdevd this is catastrophic: restarting mdevd will freqently
            # nuke the entire wayland/gui/x11 session.
            uncaughtLogs =
              spath: service:
              final.six.mkLogger {
                run = "${final.pkgs.s6-portable-utils}/bin/s6-cat";
              };

            defaultLogger = final.uncaughtLogs;
          };

        # A target is something that can be depended upon, started, or stopped.
        # Targets include:
        #
        # - Bundles (possibly empty) of other targets.
        # - Service derivations, which are specific instantiations of services.
        #   Each service expression, applied to a complete set of arguments, yields
        #   a service derivation.
        #
        # Each target has a `tname` which is the unique attrpath below `targets`
        # through which it is reachable.  The `tname` is used to identify the target
        # when issuing commands like `six start` and `six stop`.
        #
        targets = {
          default                  = final.six.mkBundle { };
          global.mounts            = final.six.mkBundle { passthru.before = [ final.targets.default ]; };
          global.coldplug          = final.six.mkBundle { };
          global.set-hostname      = final.six.mkBundle { };
          global.hwclock           = final.six.mkBundle { };
          mdevd                    = final.services.mdevd { };
          mdevd-coldplug           = final.services.mdevd-coldplug { };
          dnscache                 = final.services.dnscache { };
          nix-daemon               = final.services.nix-daemon {};
          # FIXME: logging sshd means it won't start if the root filesystem can't be remounted read-write
          sshd                     = final.services.sshd {};
          syslog                   = final.services.syslog {};
          set-hostname             = final.services.set-hostname { hostname = final.name; };
          allow-unprivileged-pings = final.services.allow-unprivileged-pings {};
          update-activated-profile = final.services.update-activated-profile {};

          # TODO: use --onlyonce mounting option?
          mounts = {
            proc = final.services.mount { where = "/proc"; };
            sys = final.services.mount { where = "/sys"; };
            dev.pts = final.services.mount { where = "/dev/pts"; };
            tmp = final.services.mount {
              where = "/tmp";
              fstype = "tmpfs";
              options = [ "nodev" "nosuid" "nr_inodes=0" "mode=1777" "size=1g" ];
            };
            dev.shm = final.services.mount {
              where = "/dev/shm";
              options = [ "size=50%" "nosuid" "nodev" "mode=1777" ];
            };
            "" = final.services.mount {
              where = "/";
              options = [ "remount" "rw" ];
            };
          };

          # FIXME: this is a mess, requires major cleanup
          net.iface = sixos.lib.pipe final.interfaces [
            (lib.mapAttrsToList
              (ifname: interface:
                if interface.type or null == "loopback"
                then lib.nameValuePair ifname (final.services.netif {
                  inherit ifname;
                  inherit (interface) type;
                  address = "127.0.0.1";
                  netmask = 8;
                }) else if interface?subnet
                   then lib.nameValuePair ifname (
                     let ifconn = final.ifconns.${interface.subnet};
                     in if ifconn?wg
                        then final.services.wireguard ((builtins.removeAttrs ifconn ["ip" "edenPort" "wg"]) // {
                          inherit ifname;
                          inherit (ifconn) mtu netmask;
                          inherit (ifconn.wg) fwmark peers;
                          private-key-filename = "/etc/wireguard/privatekey";
                          address = final.ifconns.${interface.subnet}.ip;
                          listen-port = 201;
                        })
                        else final.services.netif ((builtins.removeAttrs ifconn ["ip" "edenPort"]) // {
                          inherit ifname;
                        } // lib.optionalAttrs (final.ifconns.${interface.subnet}?ip) {
                          address = final.ifconns.${interface.subnet}.ip;
                        }))
                   else null
              ))
            (lib.filter (v: v!=null))
            (map (lib.flip infuse ({
              value.__output.passthru.before.__append = [ final.targets.default ];
            })))
            lib.listToAttrs
          ];
        };
      };

  # set system-isFooBar tags
  set-system-tags = host-final: host-prev: host-prev // {
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
  };

  build-ifconns-and-interfaces =
    # build the ifconns and interfaces attributes
    (
      (host-final: host-prev:
        let
          ifconns =
            # all the subnets to which it is directly attached.
            sixos.lib.pipe host-final.site.subnets [
              (
                lib.mapAttrs (subnetName: subnet:
                  sixos.lib.pipe subnet [
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
            sixos.lib.pipe ifconns [
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
      ));

  kernel-defaults = host-final: host-prev:
    # default kernel setup
    let
      mkKernelConsoleBootArg =
        { device
        , baud ? null }:
        "console=${device}"
        + lib.optionalString (baud!=null) ",${toString baud}";
    in infuse host-prev {
      boot.kernel.params.__init = [
        "root=${host-final.boot.rootfs.parameter}"
      ] ++ lib.optionals host-final.boot.rootfs.first-mount-is-readonly [
        "ro"
      ] ++ lib.optionals (host-final.boot?kernel.console) [
        (mkKernelConsoleBootArg host-final.boot.kernel.console)
      ] ++ [
        # To avoid having remotely-administered machines stranded at the kernel
        # panic prompt, let's boot back into the bootloader on a panic after 120
        # seconds.  FIXME: make this configurable, or omittable.  May involve
        # making kernel boot parameters into an attrset rather than a list?
        "panic=120"
      ];
      boot.kernel.modules.__init = "${lib.getOutput "modules" host-final.boot.kernel.package}";
      boot.kernel.package.__init = host-final.pkgs.callPackage sixos.mkHost.kernel { };
      boot.rootfs.label.__init = "root";
      boot.rootfs.parameter.__init = "LABEL=${host-final.boot.rootfs.label}";
      boot.rootfs.first-mount-is-readonly.__init = true;

      # If the bootloader or its configuration is stored on a mountable
      # filesystem, this should be set to that filesystem's LABEL.  Mainly
      # used for uboot.
      boot.loader.filesystem.label.__assign = "boot";

      boot.initrd.ttys.__default = { tty0 = null; };
      boot.initrd.contents.__default = { };
      boot.kernel.firmware.__default = [];
    };

  # lots of software will malfunction unless both `localhost` and the host's
  # hostname appear in /etc/hosts.
  add-hostname-and-localhost-to-etc-hosts = host-final: host-prev:
    infuse host-prev {
      etc.hosts."127.0.0.1".__append = [
        "localhost"
        host-final.name
      ];
    };

  # The `doas` program is special and privileged in sixos: it *must* be present
  # and is (ideally) the only setuid-root program on the system.
  #
  # see mkConfiguration for additional details on the symbolic links which make
  # doas work correctly.
  set-up-doas-conf = host-final: host-prev:
    infuse host-prev {
      doas-conf.__append = [
        # allows root to run `doas -u someuser ...`
        "permit nopass root"
      ] ++ lib.optionals (host-final.groups?wheel) [
        "permit nopass :wheel"
      ];
    };

in [
  init
  set-system-tags
  build-ifconns-and-interfaces
  kernel-defaults
  add-hostname-and-localhost-to-etc-hosts
  set-up-doas-conf
] ++ sixos.mkHost.initrd
