{
  nixpkgs-path
  ? builtins.fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/38edd08881ce4dc24056eec173b43587a93c990f.tar.gz";
    sha256 = "049wkiwhw512wz95vxpxx65xisnd1z3ay0x5yzgmkzafcxvx9ckw";
  },

  lib
  ? import "${nixpkgs-path}/lib",

  infuse
  ? ((import (builtins.fetchGit {
    url = "https://codeberg.org/amjoseph/infuse.nix";
    rev = "bb99266d1e65f137a38b7428a16ced77cd587abb";
    shallow = true;
  })) { inherit lib; }).v1.infuse,

  nixpkgs
  ? args:
    (import nixpkgs-path)
      (infuse args {
        overlays.__append = import ./pkgs/overlays.nix { inherit lib infuse; };
      }),

  tvl-fyi
  ? builtins.fetchGit {
    url = "https://github.com/tvl-fyi/depot";
    # feat(nix/readTree): Handle a builtins w/o scopedImport
    rev = "b0547ccfa5e74cf21e813cd18f64ef62f1bf3734";
    shallow = true;
  },

  readTree
  # This is tvl canon at dacbde58ea97891a32ce4d874aba0fc09328c1d5 plus a
  # one-line change (which I am not yet sure is appropriate for upstream) to
  # allow a `default.nix` which evaluates to an attrset to control the merging
  # of its own children by providing a `__readTreeMerge` attribute.
  ? import (builtins.fetchurl {
    url = "https://codeberg.org/amjoseph/depot/raw/commit/874181181145c7004be6164baea912bde78f43f6/nix/readTree/default.nix";
    sha256 = "1hfidfd92j2pkpznplnkx75ngw14kkb2la8kg763px03b4vz23zf";
  }) {},

  yants
  ? import (builtins.fetchurl {
    url = "https://code.tvl.fyi/plain/nix/yants/default.nix";
    sha256 = "026j3a02gnynv2r95sm9cx0avwhpgcamryyw9rijkmc278lxix8j";
  }),

  six-initrd
  ? import (builtins.fetchGit {
    url = "https://codeberg.org/amjoseph/six-initrd";
    rev = "eeba355b70b7fbc6f7f439c8a76cef9d561e03b5";
    shallow = true;
  }),

  check-types ? true,

  site,

  extra-by-name-dirs ? [],

  extra-auto-args ? {},

}@args:


let yants' = yants; in
let
  # this "patches" the version of `lib` that is passed to `yants`, wrapping
  # `tryEval` around invocations of `lib.generators.toPretty`.
  yants = yants' {
    lib = infuse lib {
      generators.toPretty = root.six.util.toPrettyTryWrapper;
    };
  };

  # automatically-provided arguments (e.g. callPackage and readTree)
  auto-args = {
    inherit lib yants infuse readTree;
    inherit types;
    inherit (root) util;
    inherit root;
    inherit auto-args;
    inherit site;
    inherit nixpkgs;
  };

  # readTree invocation on the directory containing this file
  root = readTree.fix (self: (readTree {
    args = auto-args;
    path = ./.;
  }));

  # readTree invocation on the `site` directory
  site =
    let
      site-unchecked = root.util.maybe-invoke-readTree auto-args' args.site;
      auto-args' = auto-args // extra-auto-args // {
        site = site-unchecked;
        auto-args = auto-args';
      };
    in
      #types.site
        site-unchecked;

  types = root.types { inherit (site) tags; };

  overlays = [

    # initial host set: populate attrnames from site.hosts
    (site-final: site-prev:
      #types.site
        ({
          inherit (site) subnets overlay tags globals;
          # This is a copy of site.hosts built by passing in an attrset full of
          # `throw` values as the fixpoint argument.  This ensures that the
          # `canonical` and `name` fields of `final.hosts.${name}` do not depend
          # on the fixpoint.
          hosts =
            lib.flip lib.mapAttrs site.hosts
              (name: host-func: let

                # an attrset where the forbidden (see below) attributes are
                # replaced with maximally-helpful error messages
                diagnostic-attributes = dependee: {
                  host =
                    lib.flip lib.mapAttrs site-final.hosts.${name}
                      (key: _: throw "${dependee} may not recursively depend on host.\${name}.${key}")
                    // restricted-recursive-host-fields;
                  pkgs = throw "${dependee} may not recursively depend on the pkgs attribute";

                  # TODO: this can be loosened up a bit, for access to site.globals, etc
                  site = throw "${dependee} may not recursively depend on the site attribute";
                };

                # these fields of the `host` fixpoint must not depend on any
                # part of the final result
                nonrecursive-host-fields = {
                  inherit name;
                  inherit (host-func (nonrecursive-host-fields // diagnostic-attributes "host.\${name}.canonical")) canonical;
                };

                # `tags` is allowed to be recursive only in itself (not in other attributes)
                restricted-recursive-host-fields = {
                  inherit (nonrecursive-host-fields) name canonical;
                  # may depend recursively only on the nonrecursive fields and itself
                  tags = lib.pipe restricted-recursive-host-fields [
                    (x: x // diagnostic-attributes "host.\${name}.tags")
                    host-func
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
                          in {
                            inherit name value;
                          })
                    ))
                  ];
                };

              in host-func {
                inherit (restricted-recursive-host-fields) name canonical tags;
                host = site-final.hosts.${name};
                site = site-final;
              } // {
                inherit (restricted-recursive-host-fields) name canonical tags;
              });
        }))

    # build the ifconns and interfaces attributes
    (root.util.forall-hosts (host-name: final: prev:
      let
        ifconns =
          # all the subnets to which it is directly attached.
          lib.pipe site.subnets [
            (
              lib.mapAttrs (subnetName: subnet:
                lib.pipe subnet [
                  # drop the __netmask key, which is not a host
                  (lib.filterAttrs (hostName: _:
                    !(lib.strings.hasPrefix "__" hostName)
                  ))

                  # add ${host}.netmask
                  (lib.mapAttrs
                    (hostName: ifconn: {
                      netmask = subnet.__netmask;
                    } // ifconn))
                ])
            )
            (lib.mapAttrsToList
              (subnetName: subnet:
                if subnet?${prev.name}
                then lib.nameValuePair subnetName subnet.${prev.name}
                else null))
            (lib.filter (v: v!=null))
            lib.listToAttrs
          ];
        interfaces =
          { lo.type = "loopback"; } //
          lib.pipe ifconns [
            (lib.mapAttrsToList
              (subnetName: ifconn:
                if ifconn?ifname
                then lib.nameValuePair ifconn.ifname ({
                  subnet = subnetName;
                } // lib.optionalAttrs (site.subnets.${subnetName}?__type) {
                  type = site.subnets.${subnetName}.__type;
                })
                else null))
            (lib.filter (v: v!=null))
            lib.listToAttrs
          ];
      in prev // { inherit ifconns interfaces; }
    ))

    # default kernel setup
    (root.util.forall-hosts
      (host-name: final: prev:
        let
          mkKernelConsoleBootArg =
            { device
            , baud ? null }:
            "console=${device}"
            + lib.optionalString (baud!=null) ",${toString baud}";
        in infuse prev {
          boot.kernel.params   = _: [
            "root=LABEL=boot"
            "ro"
          ] ++ lib.optionals (final.boot?kernel.console) [
            (mkKernelConsoleBootArg final.boot.kernel.console)
          ];
          boot.kernel.modules  = _: "${final.boot.kernel.package}";
          boot.kernel.payload  = _: "${final.boot.kernel.package}/bzImage";
          boot.kernel.package  = _: final.pkgs.callPackage ./kernel.nix { };
        }
      ))

    # arch stage
    (root.util.forall-hosts
      (name: final: prev: infuse prev
        ({
          x86_64-unknown-linux-gnu =
            import ./arch/amd64 {
              inherit final infuse name;
            };
          mips64el-unknown-linux-gnuabi64 =
            import ./arch/mips64 {
              inherit final infuse name;
            };
          powerpc64le-unknown-linux-gnu =
            import ./arch/powerpc64 {
              inherit final infuse name;
            };
          aarch64-unknown-linux-gnu =
            import ./arch/arm64 {
              inherit lib final infuse name;
              inherit (prev) tags;   # FIXME: use final.tags
            };
          mips-unknown-linux-gnu = {};
          armv7l-unknown-linux-gnueabi = {};
          "" = {};
        }.${prev.canonical or ""})  # FIXME: use final.canonical
      ))

  ] ++ (import ./initrd.nix { inherit lib infuse six-initrd; inherit (root) util; }) ++ [

  ] ++ (map root.util.apply-to-hosts site.overlay) ++ [

    # apply tags
  ] ++ (lib.pipe site.tags [

    (lib.mapAttrs (tag: overlay:
      root.util.forall-hosts
        (name: host-final: host-prev:
          host-prev //
          (if host-final.tags.${tag}
           then overlay host-final host-prev
           else {}))))

    lib.attrValues

    # FIXME: make attrvalues of site.tags be a list-of-extensions, not a single
    # extension -- that way concatenating the identity element has no
    # performance penalty
    #(lib.map (o: [o] ++ fixup))

    lib.flatten

  ]) ++ [

    # set defaults
    (root.util.forall-hosts
      (host-name: final: prev:
        infuse prev {
          boot.initrd.ttys.__default = { tty0 = null; };
          boot.initrd.contents.__default = { };
          boot.kernel.firmware.__default = [];
        }))

    (root.util.apply-to-hosts
      (hosts-final: hosts-prev:
        lib.flip lib.mapAttrs hosts-prev
          (name: prevHost:
            let host-final = hosts-final.${name}; in
            #let host = prevHost; in
            prevHost // {
              configuration = import ./configuration.nix {
                inherit yants lib infuse;
                host = host-final;
                overlays = host-final.service-overlays;
                six = import ./six {
                  inherit lib yants;
                  inherit (host-final) pkgs;
                  inherit extra-by-name-dirs;
                };
              };
            })
      ))

  ];

in {

  host =

    lib.pipe overlays ([
      # compose the extensions into a single (final: prev: ...)
      (lib.foldr lib.composeExtensions (_: _: {}))

      # tie the fixpoint knot
      (composed: lib.fix (final: composed final {}))

      # typecheck the result
    ] ++ lib.optionals check-types [
      types.site
    ] ++ [

      (x: x.hosts)
    ]);

}
