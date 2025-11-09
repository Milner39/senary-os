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
  tag-overlays,
  types,
}:

let
  tag-overlays-with-recursion-check =
    lib.mapAttrs
      (tag-name: overlay:
        host-final: host-prev:
        let
          host-applied = overlay host-final host-prev;
        in
          if host-applied.tags != host-prev.tags
          then throw "overlay for tag ${tag-name} attempted to modify the tags!"
          else
            # although this is equal to `host-applied` (due to the if-then
            # check), it is less strict (I think)
            host-applied // {
              inherit (host-prev) tags;
            })
      tag-overlays;

  site-overlays = [

    # initial host set: populate attrnames from site.hosts
    (site-final: site-prev:
      #types.site
        ({
          inherit (site-dir) subnets overlay globals;
          tag-overlays = tag-overlays-with-recursion-check;

          # This is a copy of site.hosts built by passing in an attrset full of
          # `throw` values as the fixpoint argument.  This ensures that the
          # `canonical` and `name` fields of `final.hosts.${name}` do not depend
          # on the fixpoint.
          hosts =
            lib.flip lib.mapAttrs site-dir.hosts
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
                          in
                            lib.nameValuePair name value
                        )
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

  ] ++ map root.lib.forall-hosts' root.mkHost.host-stages ++ [

  ] ++ site-dir.overlay ++ [

  ] ++ lib.map root.lib.forall-hosts [
    # apply tags
    (host-final: host-prev:
      lib.pipe host-final.tags [
        (lib.filterAttrs (_: v: v))
        lib.attrNames
        (lib.map (name: tag-overlays-with-recursion-check.${name} host-final))
        (lib.foldl' (acc: func: func acc // { inherit (acc) tags; }) host-prev)
      ])

  ] ++ lib.map root.lib.forall-hosts' [

    # set defaults
      (final: prev:
        infuse prev {
          boot.initrd.ttys.__default = { tty0 = null; };
          boot.initrd.contents.__default = { };
          boot.kernel.firmware.__default = [];
        })

      (host-final: host-prev:
        root.mkHost.mkHost {
          inherit host-final;
          inherit host-prev;
        })

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
