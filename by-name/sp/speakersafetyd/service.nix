{ lib
, pkgs
, six
, targets
, package ? pkgs.speakersafetyd
, user ? "_speakersafetyd"
, group ? "_audio"
}:

six.mkFunnel {

  inherit user group;

  mkdir = {
    "/run/speakersafetyd" = "0700";
  };

  run.argv = [
    "${package}/bin/speakersafetyd" "-c" "${package}/share/speakersafetyd"
  ];

  passthru.after = [ targets.global.coldplug ];

}

