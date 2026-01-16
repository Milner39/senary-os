{ lib
, pkgs
, six
, targets
, package ? pkgs.tor
, conf-file ? throw "conf-file is required"
, user ? "_tor"
, group ? "_tor"
, data-directory ? "/var/service/tor"
}:

six.mkFunnel {

  inherit user group;

  mkdir = {
    "${data-directory}" = "0700";
  };

  run.argv = [
    "${package}/bin/tor" "-f" "${conf-file}"
  ];

  passthru.after = [ targets.global.coldplug ];

}
