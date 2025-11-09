{ lib
, ...}:

{ name
, host-overlay
, host-final
, types
}:

# This is a copy of site.hosts built by passing in an attrset full of
# `throw` values as the fixpoint argument.  This ensures that the
# `canonical` and `name` fields of `final.hosts.${name}` do not depend
# on the fixpoint.
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

  # these fields of the `host` fixpoint must not depend on any
  # part of the final result
  nonrecursive-host-fields = let
    prev = (nonrecursive-host-fields // diagnostic-attributes "host.\${name}.canonical");
  in {
    inherit name;
    inherit (host-overlay prev prev) canonical;
  };

  # `tags` is allowed to be recursive only in itself (not in other attributes)
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

  host-prev = {
    inherit (restricted-recursive-host-fields) name canonical tags;
  };
in
host-overlay host-final host-prev // {
  inherit (restricted-recursive-host-fields) name canonical tags;
}
