{
  lib,
  yants,
  extra-by-name-dirs,
  mapDerivations,
  extractDerivations,
  infuse,
  root,
  ...
}:
{
  hosts-final,
  hosts-prev,
  name,
  host-prev,
}:
let

  add-spath =
    spath: v:
    v.overrideAttrs (previousAttrs: {
      passthru = previousAttrs.passthru // {
        inherit spath;
      }; });

  init = final: prev:
      prev // {

        inherit lib yants;
        #inherit (hosts-final.${name}) pkgs;

        # consider automatically allowing arguments `before` and `after` which, if
        # present, become `overrideAttrs` applied to `passthru`
        callService = path: final.callPackage path;

        six = {
          mkService       = final.callPackage ../six/mkService.nix;
          mkBundle        = final.callPackage ../six/mkBundle.nix;
          mkOneshot       = final.callPackage ../six/mkOneshot.nix;
          mkFunnel        = final.callPackage ../six/mkFunnel.nix;
          mkLogger        = final.callPackage ../six/mkLogger.nix;
          util = root.six.util { inherit (final) pkgs; };
        };

        # A service is a Nix function which can be applied to various arguments,
        # like a callPackage in nixpkgs.  Each `src/by-name/??/${name}/service.nix`
        # defines one service.  See also `targets` below, which include service
        # *derivations*.
        services =
          (lib.flip builtins.mapAttrs root.six.by-name
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
        #targets = prev.targets or { };
      };

  # After and before references must always be made via `final.${spath}`
  # references to services which are part of the top-level service set.  Because
  # there can be cyclic references (a.after = b, b.before = a) we can't test
  # them for equality.  Therefore, we identify each service by its attrname in
  # the top-level service set.  This is fundamentally what makes it possible for
  # six to (unlike NixOS) have multiple copies of the ssh daemon running, and to
  # reference that daemon without getting confused about which "sshd" the user
  # means.
  add-spaths =
    final: prev: prev // {
      targets = mapDerivations (path: v:
        if !(lib.isDerivation v)
        then v
        else if v?overrideAttrs
        then add-spath path v
        else throw "derivation does not have an .override method: ${lib.concatStringsSep "." path}")
        (prev.targets or {});
    };

  # This needs to be nearly-the-last overlay: any overlays after it must not add
  # additional services to the top-level service set.  We deliberately use
  # `final` instead of `prev` to cause an infinite recursion if any attrsets
  # after this one add new services.
  convert-before-to-after = final: prev:
    let
      beforeFunc =
        after-spath:
        lib.pipe prev.targets [
          extractDerivations
          builtins.attrValues
          (lib.filter (x: x!=null))
          (lib.filter
            (target:
              let target-before-spaths = map (x: x.passthru.spath) target.passthru.before;
              in lib.elem after-spath target-before-spaths))
          (map
            (target: (lib.attrByPath target.passthru.spath (throw "missing") final.targets)))
        ];
    in prev // {
      targets = lib.flip mapDerivations prev.targets
        (_: target:
          target.overrideAttrs
            (previousAttrs: {
              passthru = previousAttrs.passthru or {} // {
                after = previousAttrs.passthru.after or [] ++
                        beforeFunc target.passthru.spath;
              };
            })
        );
    };

  add-loggers =
    let make-logger-spath = path:
          (lib.take ((lib.length path) - 1) path) ++ [ "${lib.last path}-log" ];
    in final: prev: prev // {
      targets =
        lib.flip mapDerivations prev.targets
          (path: v:
            if false
               || v.passthru.stype or null != "longrun"
               || (v.passthru.logger or null) == false
            then v
            else let
              logger-spath = make-logger-spath path;
              logger-sname = lib.concatStringsSep "." logger-spath;
              #logger-sname = "${lib.concatStringsSep "." path}-log";
            in v.overrideAttrs (finalAttrs: previousAttrs: {
                 buildCommand = (previousAttrs.buildCommand or "") + ''
                   echo '${logger-sname}' > $out/producer-for
                 '';
                 passthru = (previousAttrs.passthru or {}) // {
                   logger = lib.getAttrByPath path (throw "missing ${lib.concatStringsSep "." path}") final.targets.loggers;
                 };
               })
          ) // {
      loggers =
        lib.flip mapDerivations prev.targets
          (path: v:
            if false
               || v.passthru.stype or null != "longrun"
               || (v.passthru.logger or null) == false
            then null
            else let
              logger-spath = make-logger-spath path;
              loggerfunc = if v.passthru.logger or null == null
                           then prev.defaultLogger
                           else v.passthru.logger;
              logger = add-spath logger-spath (loggerfunc path v);
            in logger
          );
          };
    };

  host-overlays = [
    (final: prev: infuse prev [
      ({
        targets.default = _: final.six.mkBundle { };
        targets.global.mounts = _: final.six.mkBundle { passthru.before = [ final.targets.default ]; };
        targets.global.coldplug = _: final.six.mkBundle { };
        targets.global.set-hostname = _: final.six.mkBundle { };
        targets.global.hwclock = _: final.six.mkBundle { };
        targets.net.iface = _: lib.pipe final.interfaces [
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
      })
      ({
        # TODO: use --onlyonce mounting option?
        targets.mounts = _: {
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
      })
      {
        targets = {
          mdevd = _: final.services.mdevd {
            conf = final.pkgs.callPackage ../mdev-conf.nix { host = final; };
          };
          mdevd-coldplug     = _: final.services.mdevd-coldplug { };
          dnscache           = _: final.services.dnscache { };
          nix-daemon         = _: final.services.nix-daemon {};
          # FIXME: logging sshd means it won't start if the root filesystem can't be remounted read-write
          sshd               = _: final.services.sshd {};
          syslog             = _: final.services.syslog {};
          set-hostname       = _: final.services.set-hostname { hostname = final.name; };

          # you need a nixpkgs patch for this
          #openntpd           = _: final.services.openntpd { };
        };
      }
    ])
    (final: prev: {
      defaultLogger =
        spath: service:
        let sname = lib.concatStringsSep "." spath; in
        final.six.mkLogger {
          run = let logDir = "/var/log/${sname}/";
                in final.pkgs.writeShellScript "eden-logger-${sname}" ''
                   ${final.pkgs.busybox}/bin/rm -f "${logDir}" 2>/dev/null # in case a file exists there
                   ${final.pkgs.busybox}/bin/mkdir -p "${logDir}"
                   exec ${final.pkgs.s6}/bin/s6-log s1000000 n20 t "${logDir}"
                 '';
          passthru.after = [
            final.targets.set-hostname
            final.targets.mounts.""  # cannot start logging until filesystem is read/write
          ];
        };
    })

    (final: prev:
      # this prevents the overlays from adding any new attrs to the attrset
      (lib.mapAttrs (k: _:
        ((lib.composeManyExtensions final.service-overlays) final prev).${k}) prev
      ) // {
        # avoids infinite recursion
        inherit (prev) tags;
        inherit (prev) service-overlays;
      })

    (final: prev:
      infuse prev ({
        targets.default.__output.passthru.after.__append =
          map (name: final.targets.${name})
            # FIXME: hacky
            (lib.attrNames (builtins.removeAttrs prev.targets [ "net" "default" "global" "mounts" ]))
        ;
        targets.mdevd-coldplug.__output.passthru.before.__append = [ final.targets.global.coldplug ];
        targets.set-hostname.__output.passthru.before.__append = [ final.targets.global.set-hostname ];
      }))

    # It is very important that this is the *last* overlay that adds to
    # boot.kernel.params, since `console=` parameters are order-sensitive.  We
    # need the `boot.console.device` to be the *last* `console=` parameter;
    # this makes it the "primary" console which becomes /dev/console after the
    # handoff to userspace.
    /*
                  (final: prev:
                    infuse prev ({
                      boot.kernel.params.__append = lib.optionals (final.boot?kernel.console) [
                        "console=${final.boot.kernel.console.device or "ttyS0"
                                  },${toString final.boot.kernel.console.baud}n8"
                      ];
                    }))
                    */
  ];

  host-with-overlays-applied' =
              ((lib.makeScope lib.callPackageWith (self: {})).overrideScope
                (lib.composeManyExtensions ([
                  (final: prev: host-prev)  # yuck
                  init
                ] ++ host-overlays ++ [
                  add-spaths
                  add-loggers
                  convert-before-to-after
                  (host-final: host-prev:
                    # FIXME: need to add after=target-mounts to almost everything
                    # above... right now I'm getting away with it only because of logging
                    (root.six.mkConfiguration {
                      inherit (host-final) pkgs;
                      inherit (host-final) boot sw;
                      delete-generations = host-final.delete-generations or null;
                      nixpkgs-version = "unknown-nixpkgs-version";
                      verbosity = 3;
                    }
                  ) host-final host-prev)
                ]
                )));
            in host-with-overlays-applied'
