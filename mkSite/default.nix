{
  lib,
  yants,
  extra-by-name-dirs,
  mapDerivations,
  infuse,
  root,
  six-initrd,
  extractDerivations,
  ...
}:

{
  site-dir,
  tags-unprocessed,
  types,
}:

let site = site-dir; in

let
  mkHost = root.mkHost;

  site-overlays = [

    # initial host set: populate attrnames from site.hosts
    (site-final: site-prev:
      #types.site
        ({
          inherit (site) subnets overlay globals;
          tags = tags-unprocessed;
          # This is a copy of site.hosts built by passing in an attrset full of
          # `throw` values as the fixpoint argument.  This ensures that the
          # `canonical` and `name` fields of `final.hosts.${name}` do not depend
          # on the fixpoint.
          hosts =
            lib.flip lib.mapAttrs site.hosts
              (name: host-func: let

                # an attrset where the forbidden (see below) attributes are
                # replaced with maximally-helpful error messages
                diagnostic-attributes = dependee: {
                  host =
                    lib.flip lib.mapAttrs site-final.hosts.${name}
                      (key: _: throw "${dependee} may not recursively depend on host.\${name}.${key}")
                    // restricted-recursive-host-fields;
                  pkgs = throw "${dependee} may not recursively depend on the pkgs attribute";

                  # TODO: this can be loosened up a bit, for access to site.globals, etc
                  site = throw "${dependee} may not recursively depend on the site attribute";
                };

                # these fields of the `host` fixpoint must not depend on any
                # part of the final result
                nonrecursive-host-fields = let
                  prev = (nonrecursive-host-fields // diagnostic-attributes "host.\${name}.canonical");
                in {
                  inherit name;
                  inherit (host-func prev prev) canonical;
                };

                # `tags` is allowed to be recursive only in itself (not in other attributes)
                restricted-recursive-host-fields = {
                  inherit (nonrecursive-host-fields) name canonical;
                  # may depend recursively only on the nonrecursive fields and itself
                  tags = lib.pipe restricted-recursive-host-fields [
                    (x: x // diagnostic-attributes "host.\${name}.tags")
                    (prev: host-func prev prev)
                    (x: types.set-tag-values (
                      (x.tags or {}) //

                      # This turns each of nixpkgs.lib's predicates "p" into an
                      # attribute "system-${p}" whose value is a boolean
                      # indicating whether or not the predicate matched this
                      # host's `hostPlatform`.  These attribute names will be
                      # intersected with those of site.tags, so if the site
                      # doesn't declare a "system-${p}" tag that's okay.
                      lib.flip lib.mapAttrs' lib.systems.inspect.predicates
                        (predicate-name: predicate-function:
                          let
                            inherit (nonrecursive-host-fields) canonical;
                            system = lib.systems.parse.mkSystemFromString canonical;
                            name = "system-${predicate-name}";
                            value = predicate-function system;
                          in {
                            inherit name value;
                          })
                    ))
                  ];
                };

                host-func-arg = {
                  inherit (restricted-recursive-host-fields) name canonical tags;
                };
              in
                host-func site-final.hosts.${name} host-func-arg // {
                  inherit (restricted-recursive-host-fields) name canonical tags;
                });
        }))

    # build the ifconns and interfaces attributes
    (root.lib.forall-hosts (host-name: final: prev:
      let
        ifconns =
          # all the subnets to which it is directly attached.
          lib.pipe site.subnets [
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
                } // lib.optionalAttrs (site.subnets.${subnetName}?__type) {
                  type = site.subnets.${subnetName}.__type;
                })
                else null))
            (lib.filter (v: v!=null))
            lib.listToAttrs
          ];
      }
    ))

    # default kernel setup
    (root.lib.forall-hosts
      (host-name: final: prev:
        let
          mkKernelConsoleBootArg =
            { device
            , baud ? null }:
            "console=${device}"
            + lib.optionalString (baud!=null) ",${toString baud}";
        in infuse prev {
          boot.kernel.params   = _: [
            "root=LABEL=boot"
            "ro"
          ] ++ lib.optionals (final.boot?kernel.console) [
            (mkKernelConsoleBootArg final.boot.kernel.console)
          ];
          boot.kernel.modules  = _: "${final.boot.kernel.package}";
          boot.kernel.payload  = _: "${final.boot.kernel.package}/bzImage";
          boot.kernel.image    = _: "${final.boot.kernel.package}/vmlinux";
          boot.kernel.package  = _: final.pkgs.callPackage ../kernel.nix { };
          boot.rootfs.label.__assign = "root";
          boot.loader.filesystem.label.__assign = "boot";
        }
      ))

    # arch stage is allowed to alter the tags
    (root.lib.forall-hosts'
      (name: final: prev: infuse prev
        ({
          x86_64-unknown-linux-gnu =
            import ../arch/amd64 {
              inherit final infuse name;
            };
          mips64el-unknown-linux-gnuabi64 =
            import ../arch/mips64 {
              inherit final infuse name;
            };
          powerpc64le-unknown-linux-gnu =
            import ../arch/powerpc64 {
              inherit final infuse name;
            };
          aarch64-unknown-linux-gnu =
            import ../arch/arm64 {
              inherit lib final infuse name;
            };
          mips-unknown-linux-gnu = {};
          armv7l-unknown-linux-gnueabi = {};
          "" = {};
        }.${prev.canonical or ""})  # FIXME: use final.canonical
      ))

  ] ++ (root.initrd) ++ [

  ] ++ (map root.lib.apply-to-hosts site.overlay) ++ [

    # apply tags
  ] ++ (lib.pipe tags-unprocessed [

    (lib.mapAttrs (tag: overlay:
      root.lib.forall-hosts
        (name: host-final: host-prev:
         host-prev //
          (if host-final.tags.${tag}
           then overlay host-final host-prev
           else {}))))

    lib.attrValues

    # FIXME: make attrvalues of site.tags be a list-of-extensions, not a single
    # extension -- that way concatenating the identity element has no
    # performance penalty
    #(lib.map (o: [o] ++ fixup))

    lib.flatten

  ]) ++ [

    # set defaults
    (root.lib.forall-hosts
      (host-name: final: prev:
        infuse prev {
          boot.initrd.ttys.__default = { tty0 = null; };
          boot.initrd.contents.__default = { };
          boot.kernel.firmware.__default = [];
        }))

    (root.lib.apply-to-hosts
      (hosts-final: hosts-prev:
        lib.flip lib.mapAttrs hosts-prev
          (name: host-prev:
            mkHost {
              inherit hosts-final;
              inherit hosts-prev;
              inherit name;
              inherit host-prev;
            })))

  ] ++ [

    # Add `site.host.${name}.site==site` (only in the `final` parameter, so this
    # overlay must go last).
    (site-final: site-prev: site-prev // {
      hosts = lib.mapAttrs (name: host-prev:
        host-prev // {
          site = site-final;
        }) site-prev.hosts;
    })
  ];
in
site-overlays
