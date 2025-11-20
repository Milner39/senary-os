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

[
  # initial host set: populate attrnames from site.hosts
  (site-final: site-prev:
    #types.site
    ({
      inherit (site-dir) subnets overlay globals;
      tag-overlays =
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

] ++ map sixos.lib.forall-hosts sixos.mkHost.host-stages ++ [

] ++ site-dir.overlay ++ [

] ++ lib.map sixos.lib.forall-hosts [

  sixos.mkHost.mkHost

] ++ [

  # Add `site` attribute to each host, but do this only after all user
  # overlays so they can't accidentally use `host-prev.site`.
  (site-final: site-prev: site-prev // {
    hosts = lib.mapAttrs (name: host-prev:
      host-prev // {
        site = site-final;
      }) site-prev.hosts;
  })
]
