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
    rev = "73c5111fdb7c0faab55bd9a19b26821639a4258e";
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
      generators.toPretty = sixos.lib.toPrettyTryWrapper;
    };
  };

  # readTree invocation on the sixos source code
  sixos =
    lib.filterAttrsRecursive
      (name: value: !(lib.hasPrefix "__readTree" name))
      (readTree.fix (self: (readTree {
        path = ./.;
        args = {
          inherit lib yants infuse readTree;
          inherit (site) types;
          inherit sixos;
          inherit nixpkgs;
          inherit extra-by-name-dirs six-initrd;
        };
      })));

  # readTree invocation on the `site` directory.  This is done as a convenience,
  # to avoid the site repository needing to fetchGit readTree and yants like
  # sixos does.
  site-dir =
    let
      site-dir-unchecked =
        sixos.lib.maybe-invoke-readTree
          ({
            inherit lib yants infuse readTree;
            inherit (site) types;
            inherit sixos;
          } // extra-auto-args // {
            site = site-dir-unchecked;
          })
          args.site-dir;
    in
      (if check-types
       then site.types.site-dir
       else lib.id)
        site-dir-unchecked;

  site =
    sixos.mkSite {
      inherit site-dir;
      tag-definitions =
        sixos.tags //
        lib.flip lib.mapAttrs site-dir.tags
          (tag-name: site-tag-definition:
            if sixos.tags?${tag-name}
            then {
              implies = (sixos.tags.${tag-name}.implies or {}) // (site-tag-definition.implies or {});
              overlays = sixos.tags.${tag-name}.overlays ++ site-tag-definition.overlays;
            } else site-tag-definition);
    };

in

# typecheck the result *after* the fixpoint (otherwise we get infinite
# recursion because yants checking is strict)
(if check-types then site.types.site else lib.id) site

