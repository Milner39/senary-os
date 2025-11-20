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

  # initial site
  site-initial = {
    inherit types;
    inherit (site-dir) subnets globals;
    tag-overlays =
      lib.mapAttrs
        sixos.lib.add-tag-mutation-check-to-overlay
        tag-overlays;

    # initial host set: populate attrnames from site.hosts
    hosts =
      lib.mapAttrs
        (name: host-overlay: { inherit name; })
        site-dir.hosts;
  };

  overlays = [

    # apply mkHost.host-stages to each host
  ] ++ map sixos.lib.forall-hosts (sixos.mkHost.host-stages site-dir.hosts) ++ [

    # apply the site-dir's sitewide overlay
  ] ++ site-dir.overlay ++ [

    # finish up the hosts
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
  (composed: lib.fix (final: composed final site-initial))
]
