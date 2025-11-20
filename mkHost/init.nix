{ lib
, sixos
, types
, ...}:

{ name
, canonical
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
  host-initial = {
    inherit name;
    inherit canonical;
    tags = types.default-tag-values;
  };
in
host-initial

