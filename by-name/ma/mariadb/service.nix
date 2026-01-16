{ lib
, pkgs
, six
, targets
, user ? "_mariadb"
, group ? "_mariadb"
, package ? pkgs.mariadb
, data_directory ? throw "you must specify data_directory"
, extraConfig ? {}
}:

six.mkFunnel {

  inherit user group;

  data = {
    "mariadb.conf" = pkgs.writeText "mariadb-mariadb.conf" config;
  };

  run = {
    pre-argvs = [
      [ "${pkgs.busybox}/bin/mkdir" "-p" "/run/mariadb" ]
      [ "${pkgs.busybox}/bin/chown" "${user}:${group}" "/run/mariadb" ]
      [ "${pkgs.busybox}/bin/chmod" "g+rw" "/run/mariadb" ]
    ];
    argv = [
      "${package}/bin/mariadb"
    ];
  };

  passthru.after = [ targets.global.coldplug ];

}

