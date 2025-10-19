{ lib
, pkgs
, six
, targets
, package ? pkgs.tor
, conf-file ? throw "conf-file is required"
, user-name ? throw "user-name is required"
, group-name ? throw "group-name is required"
, data-directory
}:

six.mkFunnel {

  run =
    six.util.depot.writeExecline
      "service.tor.run"
      { argMode = "none"; }
      (six.util.execline.seq [
        [ "${pkgs.busybox}/bin/mkdir" "-p" data-directory ]
        [ "${pkgs.busybox}/bin/chown" "${user-name}:${group-name}" data-directory ]
        (six.util.chpst {
          user = user-name;
          group = group-name;
          argv = [
            "${package}/bin/tor" "-f" "${conf-file}"
          ];
        })
      ]);

  passthru.after = [ targets.global.coldplug ];

}
