{
  lib,
  yants,
  extra-by-name-dirs,
  infuse,
  sixos,
  ...
}:

{
  site-dir,
  tag-overlays,
}:

let
  types = sixos.types { inherit tag-overlays; };

  overlays = [
    (site-final: site-prev: {
      inherit types;
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
  ];
in
lib.pipe overlays [
  # compose the extensions into a single (final: prev: ...)
  (lib.foldr lib.composeExtensions (_: _: {}))

  # tie the fixpoint knot
  (composed: lib.fix (final: composed final {}))
]
