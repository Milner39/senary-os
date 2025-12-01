# sixos utility functions that do not require a nixpkgs `pkgs` packageset
{
  lib,    # from nixpkgs
  yants,
  readTree,
  infuse,
  ...
}:

let
  # copied from unmerged https://github.com/NixOS/nixpkgs/pull/235230
  canonicalize = let
    tripleFromSystem = { cpu, vendor, kernel, abi, ... } @ sys:
      let
        kernel' = lib.systems.parse.kernelName kernel;
        optAbi = lib.optionalString (abi.name != "") "-${abi.name}";
        optVendor = lib.optionalString (vendor.name != "") "-${vendor.name}";
        optKernel = lib.optionalString (kernel' != "") "-${kernel'}";
      in
        # gnu-config considers "mingw32" and "cygwin" to be kernels.
        # This is obviously bogus, which is why nixpkgs has historically
        # parsed them differently.  However for regression testing
        # reasons (see lib/tests/triples.nix) we need to replicate this
        # quirk when unparsing in order to round-trip correctly.
        if      abi == "cygnus"     then "${cpu.name}${optVendor}-cygwin"
        else if kernel == "windows" then "${cpu.name}${optVendor}-mingw32"
        else "${cpu.name}${optVendor}${optKernel}${optAbi}";
  in
    lib.flip lib.pipe [
      lib.systems.parse.mkSystemFromString
      tripleFromSystem
    ];

  #
  # To avoid the site repository needing to fetchGit readTree and
  # yants, we optionally allow the hosts and tags attrsets to be
  # passed as directories and invoke readTree on them.
  #
  maybe-invoke-readTree = args: arg:
    if lib.isPath arg
    then
      lib.filterAttrsRecursive
        (name: value: !(lib.hasPrefix "__readTree" name))
        (readTree.fix (self: (readTree {
          inherit args;
          path = arg;
          rootDir = false;
        })))
    else arg;

  #
  # Nix attrsets are strict in their attrnames.  Applying this function to a
  # `host` attrset ensures that the result's attrnames are statically
  # determined.  Doing this within a fixpoint avoids a lot of very hard-to-debug
  # infinite recursions.
  #
  make-host-attrnames-deterministic =
    host:
    let
      defaults = {
        name = throw "missing name";
        canonical = "missing canonical";
        tags = {};
        interfaces = {};
        ifconns = {};
        pkgs = throw "missing pkgs";
        sw = throw "missing sw";
        configuration = throw "missing configuration";
        delete-generations = null;
        service-overlays = [];
        boot = {};
        users = {};
        groups = {};
        targets = {};
        six = {};
        services = {};
        callService = throw "missing";
        callPackage = throw "missing";
      };
    in
      builtins.intersectAttrs
        (defaults // { hostid = throw "bogus"; })
        (builtins.mapAttrs
          (k: v: host.${k} or v)
          defaults);

  #
  # Turns an overlay-on-hosts into an overlay-on-a-site
  #
  apply-to-hosts =
    hosts-overlay:
    site-final: site-prev:
    site-prev // {
      hosts = site-prev.hosts // hosts-overlay site-final.hosts site-prev.hosts;
    };

  #
  # Turns an overlay-on-one-host into an overlay-on-the-set-of-hosts; also does
  # applies `make-host-attrnames-deterministic` after each overlay to prevent
  # infinite recursions.
  #
  forall-hosts = host-overlay:
    apply-to-hosts
      (hosts-final: hosts-prev:
        lib.mapAttrs
          (name: host-prev:
            (make-host-attrnames-deterministic
              (host-prev
               // (host-overlay hosts-final.${name} host-prev))
            ))
          hosts-prev
      );

  # The following is copy-pasted from infuse.nix, which uses this routine but
  # does not expose it (since doing so would make it part of the infuse API).
  #
  # This is a `throw`-tolerant version of toPretty, so that error diagnostics in
  # this file will print "<<throw>>" rather than triggering a cascading error.
  #
  toPrettyTryWrapper = old-toPretty:
    args: val:
    let
      try = builtins.tryEval (old-toPretty args val);
    in
      if try.success
      then try.value
      else "<<throw>>";

  toPrettyTry = toPrettyTryWrapper lib.generators.toPretty;

  # walk a tree of attrsets, applying a function to any derivations
  mapDerivations = let
    mapDerivations' =
      path: f: val:
      if lib.isDerivation val
      then f path val
      else if !(lib.isAttrs val)
      then val
      else lib.mapAttrs
        (k: v: mapDerivations' (path ++ [k]) f v)
        val;
  in
    mapDerivations' [];

  # walks a tree of attrsets, extracting attrvalues which are derivations
  extractDerivations = let
    flatten' =
      path: val:
      if !(lib.isAttrs val) || lib.isDerivation val
      then [(lib.nameValuePair (lib.concatStringsSep "." path) val)]
      else lib.concatLists
        (lib.mapAttrsToList
          (k: v: flatten' (path ++ [k]) v)
          val);
    in
      attrs:
      lib.pipe attrs [
        (lib.mapAttrsToList (k: v: flatten' [k] v))
        lib.concatLists
        lib.listToAttrs
      ];

  # A version of builtins.toString that does the sane thing to booleans,
  # rendering false as "false" (instead of "0") and true as "true" instead of
  # "1"
  toString = arg:
    if lib.isBool arg
      then if arg
           then "true"
           else "false"
    else
      builtins.toString arg;


  #
  # builtins.foldl' is stricter than you would expect; it diverges if *any* of
  # the accumulated values diverges, rather than only if the *last* accumulator
  # value diverges.  Example:
  #
  #  builtins.foldl' (x: f: f x) 0 [ (_: throw "fail") (_: 3) ]
  #
  # Since nixpkgs' lib.pipe is defined in terms of builtins.foldl', it inherits
  # this problem.  So we define a lazier version using foldl instead of foldl'.
  #
  pipe = lib.foldl (x: f: f x);

  # Given a tag and its overlay, wrap the overlay with a check that the overlay
  # did not try to modify the tags.  This is important because (for infinite
  # recursion reasons) we must silently discard any attempts by a tag overlay to
  # mutate the tags.
  add-tag-mutation-check-to-overlay =
    tag-name: overlay:
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
        };

  # Convert an attribute into a command-line flag.
  #
  # - Keys which do not start with "-" are prefixed with "--" if their
  #   stringLength is at least 2 and "-"otherwise.
  #
  # - Non-null values are converted into a string (see six.lib.toString) and
  #   prefixed with "="
  #
  attrToFlag = key: val:
    lib.concatStrings ([
      (if lib.strings.hasPrefix "-" key
       then ""
       else if builtins.stringLength key <= 1
       then "-"
       else "--")
      key
    ] ++ lib.optionals (val!=null) [
      "="
    ] ++ [
      (toString val)
    ]);

  # Convert an attrset into a list of command-line flags
  attrsToFlags = attrs: lib.mapAttrsToList attrToFlag attrs;

in {
  inherit
    pipe
    canonicalize
    maybe-invoke-readTree
    forall-hosts
    make-host-attrnames-deterministic
    toPrettyTryWrapper
    toPrettyTry
    mapDerivations
    extractDerivations
    add-tag-mutation-check-to-overlay
    toString
    attrsToFlags
    ;
}

