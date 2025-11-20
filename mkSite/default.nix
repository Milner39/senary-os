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
  (site-final: site-prev: {
    inherit (site-dir) subnets globals;
    tag-overlays =
      lib.mapAttrs
        sixos.lib.add-tag-mutation-check-to-overlay
        tag-overlays;

    # initial host set: populate attrnames from site.hosts
    hosts =
      lib.flip lib.mapAttrs site-dir.hosts
        (name: host-overlay:
          sixos.mkHost.init {
            host-final = site-final.hosts.${name};
            inherit host-overlay;
            inherit types;
            inherit name;
          });
  })

] ++ map sixos.lib.forall-hosts sixos.mkHost.host-stages ++ [

] ++ site-dir.overlay ++ [

  (sixos.lib.forall-hosts sixos.mkHost.mkHost)

] ++ [

  # Add the `site` attribute to each host, but do this only after all user
  # overlays so they can't accidentally use `host-prev.site`.
  (site-final: site-prev: site-prev // {
    hosts = lib.mapAttrs (name: host-prev:
      host-prev // {
        site = site-final;
      }) site-prev.hosts;
  })
]
