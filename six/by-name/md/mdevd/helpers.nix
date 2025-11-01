{ lib
, stdenv
, pkgs
, alsaSupport ? !stdenv.hostPlatform.isMips
}:

let
  pname = "mdev-like-a-boss";
  version = "20200119";
in
stdenv.mkDerivation {
  inherit pname version;
  src = pkgs.fetchFromGitHub {
    owner = "slashbeast";
    repo = pname;
    rev = "f77310ea8e039282a545f17df676f2e42f112746";
    hash = "sha256-dGUSyE4/0od7CGM600+51JZZsJtYt1qLK2oSa92blzw=";
  };
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
    wrapProgram $out/bin/sound-control  --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils alsa-utils ]}
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
