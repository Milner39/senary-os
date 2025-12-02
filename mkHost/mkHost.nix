{
  lib,
  yants,
  extra-by-name-dirs,
  infuse,
  sixos,
  ...
}:

#
# This file contains the single-host overlays that are applied *after* any of
# the site-specific overlays.
#

let

  add-spath =
    spath: v:
    v.overrideAttrs (previousAttrs: {
      passthru = previousAttrs.passthru // {
        inherit spath;
      }; });

  apply-tags =
    (host-final: host-prev:
      (sixos.lib.pipe host-final.tags [
        (lib.filterAttrs (_: v: v))   # filter out the unset tags
        lib.attrNames                 # gather the attrnames

        # for each attname, get the corresponding overlay
        (lib.map (name:
          host-final.site.tag-overlays.${name}))

        # compose the overlays and apply them to host-prev
        (overlays: lib.composeManyExtensions overlays host-final host-prev)

        # Prevent the tag overlays from introducing new attrnames (causes
        # infinite recursion) -- FIXME: try to find the tag overlay that is
        # doing this and fix it there so this can be removed.
        (sixos.lib.make-host-attrnames-deterministic host-final.site)

        # Prevent tag overlays from changing the tags themselves (FIXME: lift
        # this restriction)
        (host: host // { inherit (host-prev) tags canonical; })
      ]));

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
      targets = sixos.lib.mapDerivations (path: v:
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
        sixos.lib.pipe prev.targets [
          sixos.lib.extractDerivations
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
      targets = lib.flip sixos.lib.mapDerivations prev.targets
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
        lib.flip sixos.lib.mapDerivations prev.targets
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
        lib.flip sixos.lib.mapDerivations prev.targets
          (path: v:
            if false
               || v.passthru.stype or null != "longrun"
               || (v.passthru.logger or null) == false
            then null
            else let
              logger-spath = make-logger-spath path;
              loggerfunc = if v.passthru.logger or null == null
                           then final.defaultLogger
                           else v.passthru.logger;
              logger = add-spath logger-spath (loggerfunc path v);
            in logger
          );
          };
    };

  add-default-logger =
    (final: prev: prev // {
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
    });

  add-default-target =
    (final: prev:
      infuse prev ({
        targets.default.__output.passthru.after.__append =
          map (name: final.targets.${name})
            # FIXME: hacky
            (lib.attrNames (builtins.removeAttrs prev.targets [ "net" "default" "global" "mounts" ]))
        ;
      }));

  # It is very important that this is the *last* overlay that adds to
  # boot.kernel.params, since `console=` parameters are order-sensitive.  We
  # need the `boot.console.device` to be the *last* `console=` parameter;
  # this makes it the "primary" console which becomes /dev/console after the
  # handoff to userspace.
  add-early-console-bootparam =
    (final: prev:
      infuse prev ({
        # temporarily disabled (why?)
        /*
        boot.kernel.params.__append = lib.optionals (final.boot?kernel.console) [
          "console=${final.boot.kernel.console.device or "ttyS0"
                    },${toString final.boot.kernel.console.baud}n8"
        ];
        */
      }));


  # FIXME: need to add after=target-mounts to almost everything
  # above... right now I'm getting away with it only because of logging

  mkHost = [
    apply-tags
    add-default-logger
    add-default-target
    sixos.mkHost.users.synthesize-groups
    add-early-console-bootparam
    add-spaths
    add-loggers
    convert-before-to-after
    (sixos.mkConfiguration {})
  ];

in
mkHost
