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
  performance-troubleshooting = false;

  types = sixos.types { inherit tag-overlays; };

  # initial site
  site-initial = {
    inherit types;
    inherit (site-dir) subnets globals;
    tag-overlays = tag-overlays;

    # initial host set: populate attrnames from site-dir.hosts
    hosts =
      lib.mapAttrs
        (name: host-overlay: { inherit name; })
        site-dir.hosts;
  };

  overlays = [

  ] ++ map sixos.lib.forall-hosts sixos.mkHost.before-site-overlay ++ [

    # apply host overlays from the site-dir
    (sixos.lib.forall-hosts
      (host-final: host-prev:
        host-prev //
        site-dir.hosts.${host-prev.name}
          host-final
          host-prev))

    # apply the site-dir's sitewide overlay
  ] ++ site-dir.overlay ++ [

    # finish up the hosts
  ] ++ map sixos.lib.forall-hosts sixos.mkHost.after-site-overlay ++ [

  ] ++ lib.optionals performance-troubleshooting [

    # For performance troubleshooting
    (sixos.lib.forall-hosts
      (host-final: host-prev:
        lib.flip lib.mapAttrs host-prev
          (name: val:
            if name == "name" || name == "site" then val else
            lib.trace "forced thunk: site.hosts.${host-final.name}.${name}" val)))

  ] ++ [

    # Add the `site` attribute to each host, but do this only after all user
    # overlays so they can't accidentally use `host-prev.site`.
    (site-final: site-prev: infuse site-prev {
      hosts.__values.site.__assign = site-final;
    })

    # Make the attrnames of host-final independent of any of the overlays
    # anywhere in the fixpoint.  This cures a lot of hard-to-debug infinite
    # recursions.
    (site-final: site-prev: site-prev // {
      hosts =
        lib.mapAttrs
          (name: host-prev:
            sixos.lib.make-host-attrnames-deterministic site-final host-prev)
          site-prev.hosts;
    })

  ];
in

sixos.lib.pipe overlays [
  # compose the extensions into a single (final: prev: ...)
  (lib.foldr lib.composeExtensions (_: _: {}))

  # tie the fixpoint knot
  (composed: lib.fix (final: composed final site-initial))
]
