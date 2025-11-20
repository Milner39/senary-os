{
  lib,
  yants,
  extra-by-name-dirs,
  infuse,
  sixos,
  six-initrd,
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

          hosts =
            lib.flip lib.mapAttrs site-dir.hosts
              (name: host-overlay:
                sixos.mkHost.init {
                  host-final = site-final.hosts.${name};
                  inherit host-overlay;
                  inherit types;
                  inherit name;
                });
        }))

  ] ++ map sixos.lib.forall-hosts' sixos.mkHost.host-stages ++ [

  ] ++ site-dir.overlay ++ [

  ] ++ lib.map sixos.lib.forall-hosts [
    # apply tags
    (host-final: host-prev:
      lib.pipe host-final.tags [
        (lib.filterAttrs (_: v: v))
        lib.attrNames
        (lib.map (name: tag-overlays-with-recursion-check.${name} host-final))
        (lib.foldl' (acc: func: func acc // { inherit (acc) tags; }) host-prev)
      ])

  ] ++ lib.map sixos.lib.forall-hosts' [

    # set defaults
      (final: prev:
        infuse prev {
          boot.initrd.ttys.__default = { tty0 = null; };
          boot.initrd.contents.__default = { };
          boot.kernel.firmware.__default = [];
        })

      (host-final: host-prev:
        sixos.mkHost.mkHost {
          inherit host-final;
          inherit host-prev;
        })

  ] ++ [

    # Add `site.host.${name}.site`, but only after all user overlays.  This
    # forces user overlays to reach it by way of `host-final.site` so they don't
    # accidentally use `host-prev.site`.
    (site-final: site-prev: site-prev // {
      hosts = lib.mapAttrs (name: host-prev:
        host-prev // {
          site = site-final;
        }) site-prev.hosts;
    })
  ];
in
site-overlays
