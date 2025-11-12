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

  site-dir,

  extra-by-name-dirs ? [],

  extra-auto-args ? {},

}@args:


let yants' = yants; in
let
  # this "patches" the version of `lib` that is passed to `yants`, wrapping
  # `tryEval` around invocations of `lib.generators.toPretty`.
  yants = yants' {
    lib = infuse lib {
      generators.toPretty = root.lib.toPrettyTryWrapper;
    };
  };

  # automatically-provided arguments (e.g. callPackage and readTree)
  auto-args = {
    inherit lib yants infuse readTree;
    inherit types;
    inherit root;
    inherit auto-args;
    inherit nixpkgs;
    inherit extra-by-name-dirs six-initrd;
  };

  # readTree invocation on the directory containing this file
  root = readTree.fix (self: (readTree {
    args = auto-args;
    path = ./.;
  }));

  # readTree invocation on the `site` directory
  site-dir =
    let
      site-unchecked = root.lib.maybe-invoke-readTree auto-args' args.site-dir;
      auto-args' = {
        inherit lib yants infuse readTree;
        inherit types;
      } // extra-auto-args // {
        site = site-unchecked;
        auto-args = auto-args';
      };
    in
      types.site-dir
        site-unchecked;

  tag-overlays = lib.attrsets.unionOfDisjoint root.tags site-dir.tags;

  types = root.types { tag-overlays = tag-overlays; };

  site =
    lib.pipe (root.mkSite {
      inherit site-dir tag-overlays types;
    }) ([
      # compose the extensions into a single (final: prev: ...)
      (lib.foldr lib.composeExtensions (_: _: {}))

      # tie the fixpoint knot
      (composed: lib.fix (final: composed final {}))

      # typecheck the result
    ] ++ lib.optionals check-types [
      types.site
    ]);

in {
  host = site.hosts;
}
