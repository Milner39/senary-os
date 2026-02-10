{ lib
, ...
}:

# from pkgs
{ stdenv
, buildLinux
, fetchurl
, fetchpatch
, linuxKernel
, runCommand
, overrideWithDistCC

# kernel source tarball
, version ? "6.6.41"
, source ? fetchurl {
  url = "mirror://kernel/linux/kernel/v${lib.versions.major version}.x/linux-${version}.tar.xz";
  hash = "sha256-nsmcV4FYq4XZmzd5GnZkPS6kw/cuy+97XrbWDz3gMu8=";
}

# configurables
, ignoreConfigErrors ? true
, enableDistCC ? false

# used only for gru-kevin (FIXME: remove this)
, dotconfig ? null

# used only for octeon (FIXME: remove this)
, defconfig ? (if stdenv.hostPlatform.isMips then "cavium_octeon_defconfig" else null)

# TODO: set this to `false` on more platforms
, enableCommonStructuredConfig ? with stdenv.hostPlatform; isx86_64 || isPower64

# unlike NixOS, the values of this attrset are single-character strings -- one of "y", "n", or "m"
, structuredExtraConfig ? {}

# ordinary patches (i.e. paths), not the fancy kernelPatches used in nixpkgs
, patches ? []
}:

let stdenv' = stdenv; in
let stdenv = if enableDistCC then overrideWithDistCC stdenv' else stdenv'; in
let structuredExtraConfig' = structuredExtraConfig; in

let
  commonargs = {
    src = source;
    inherit version;

    # branchVersion needs to be x.y
    extraMeta.branch = lib.versions.majorMinor version;

    kernelPatches = patches;
  };
in

    if dotconfig!=null

      # gru-kevin only
    then linuxKernel.manualConfig.override { inherit stdenv; }
      (commonargs // {
        configfile =
          if !enableDistCC
          then dotconfig
          else runCommand "config-without-plugins" {} ''
            cat ${dotconfig} | grep -v ^CONFIG_GCC_PLUGIN > $out
            echo 'CONFIG_HAVE_GCC_PLUGINS=n' >> $out
            echo 'CONFIG_GCC_PLUGINS=n' >> $out
          '';
        config = {
          CONFIG_MODULES = "y";
          CONFIG_FW_LOADER = "m";
          #CONFIG_RUST = if withRust then "y" else "n";
        };
      })

    else buildLinux (commonargs // {
      inherit defconfig;
      inherit enableCommonStructuredConfig;
      inherit ignoreConfigErrors;
      structuredExtraConfig =
        lib.flip lib.mapAttrs (import ./kernel-config.nix // structuredExtraConfig')
          (name: value:
            lib.mkForce ({
              n = lib.kernel.no;
              m = lib.kernel.module;
              y = lib.kernel.yes;
            }.${lib.toLower (toString value)} or (lib.kernel.freeform (toString value))))
      ;

    })
