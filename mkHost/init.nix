{ lib
, ...}:

{ name
, host-overlay
, host-final
, types
}:

#
# This file constructs the initial "blank" attrset for a host and passes it to
# the host-overlay (which comes from the site-dir).  It then enforces certain
# dependency requirements to avoid infinite recursion headaches:
#
# - The `name` attribute may not depend on any other attribute
# - The `canonical` attribute may depend on only the `name` attribute
# - The `tags` attribute may depend only on itself, `name`, and `canonical`
#
# This file is also responsible for setting the `system-isFooBar` tags (like
# `system-isAarch64`) based on `canonical`.
#

let
  # an attrset where the forbidden (see below) attributes are
  # replaced with maximally-helpful error messages
  diagnostic-attributes = dependee: {
    host =
      lib.flip lib.mapAttrs host-final
        (key: _: throw "${dependee} may not recursively depend on host.\${name}.${key}")
      // restricted-recursive-host-fields;
    pkgs = throw "${dependee} may not recursively depend on the pkgs attribute";

    # TODO: this can be loosened up a bit, for access to site.globals, etc
    site = throw "${dependee} may not recursively depend on the site attribute";
  };

  # The `name` and `canonical` attribute of the `host` fixpoint must not depend on
  # any part of the final result.
  nonrecursive-host-fields = let
    prev = (nonrecursive-host-fields // diagnostic-attributes "host.\${name}.canonical");
  in {
    inherit name;
    inherit (host-overlay prev prev) canonical;
  };

  # The `tags` attribute of the `host` fixpoint may depend on itself, but not on
  # any other attribute.
  restricted-recursive-host-fields = {
    inherit (nonrecursive-host-fields) name canonical;

    # may depend recursively only on the nonrecursive fields and itself
    tags = lib.pipe restricted-recursive-host-fields [
      (x: x // diagnostic-attributes "host.\${name}.tags")
      (prev: host-overlay prev prev)
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

  host-initial = {
    inherit (restricted-recursive-host-fields) name canonical tags;
  };
in
host-initial // host-overlay host-final host-initial
