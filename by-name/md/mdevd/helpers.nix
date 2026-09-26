{ lib
, stdenv
, pkgs
, alsaSupport ? !stdenv.hostPlatform.isMips
}:

let
  pname = "mdev-like-a-boss";
  version = "20200119";

  # We only need `amixer` and `alsactl`.  Since we don't need
  # ${alsa-utils}/bin/aplay, which drags in ffmpeg and ruby and a bunch of other
  # build/closure-bloat
  alsa-utils' = pkgs.alsa-utils.override {
    alsa-plugins = pkgs.runCommand "fake-alsa-plugins" {} ''
      mkdir -p $out/lib/alsa-lib
    '';
  };
in
stdenv.mkDerivation {
  inherit pname version;

  # `helpers/` and `LICENSE` from github.com/slashbeast/mdev-like-a-boss
  # at f77310ea8e039282a545f17df676f2e42f112746
  # The upstream repository has been deleted.
  src = ./mdev-like-a-boss;
  nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
  '' + lib.optionalString alsaSupport ''
    substituteInPlace helpers/sound-control \
      --replace "alsactl " \
                "alsactl -f /run/alsa-state "
  '' + ''
    mkdir $out
    mv helpers $out/bin
  '' + lib.optionalString alsaSupport ''
    wrapProgram $out/bin/sound-control  --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils alsa-utils' ]}
  '' + lib.optionalString (!alsaSupport) ''
    rm -f $out/bin/sound-control
  '' + ''
    wrapProgram $out/bin/settle-nics    --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils iproute2 nettools]}
    wrapProgram $out/bin/dev-bus-usb    --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils gnugrep ]}
    wrapProgram $out/bin/storage-device --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils gawk util-linux ]}
    chmod +x $out/bin/*
    runHook postInstall
  '';
}
