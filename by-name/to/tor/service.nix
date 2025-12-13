{ lib
, pkgs
, six
, targets
, package ? pkgs.tor
, conf-file ? throw "conf-file is required"
, user ? "_tor"
, group ? "_tor"
, data-directory
}:

six.mkFunnel {

  inherit user group;

  run = {
    pre-argvs = [
      [ "${pkgs.busybox}/bin/mkdir" "-p" data-directory ]
      [ "${pkgs.busybox}/bin/chown" "${user-name}:${group-name}" data-directory ]
    ];
    argv = [
      "${package}/bin/tor" "-f" "${conf-file}"
    ];
  };

  passthru.after = [ targets.global.coldplug ];

}
