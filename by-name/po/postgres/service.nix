{ lib
, pkgs
, six
, targets
, user ? "postgres"
, group ? "postgres"
, data_directory ? throw "you must specify data_directory"
, extraConfig ? {}
}:

let

  # probably belongs in nixpkgs/lib
  escapeSqlString =
    v: "'${lib.replaceStrings [ "'" ] [ "''" ] v}'";

  writePostgresConfig = attrs:
    lib.pipe attrs [
      (lib.mapAttrsToList (k: v: "${k} = ${escapeSqlString "${v}"}"))
      (lib.concatStringsSep "\n")
    ];

  config = writePostgresConfig ({
    inherit data_directory;
    hba_file = pkgs.writeText "postgres-hba_file" ''
      local all postgres         peer map=postgres
      local all all              peer map=postgres
      host  all all 127.0.0.1/32 md5
    '';
    ident_file = pkgs.writeText "postgres-ident_file" ''
      postgres root postgres
      postgres bitmagnet postgres
    '';
  } // extraConfig);
in

six.mkFunnel {

  data = {
    "postgresql.conf" = pkgs.writeText "postgres-postgresql.conf" config;
  };

  run = {
    pre-argv = [
      [ "${pkgs.busybox}/bin/mkdir" "-p" "/run/postgresql" ]
      [ "${pkgs.busybox}/bin/chown" "${user}:${group}" "/run/postgresql" ]
      [ "${pkgs.busybox}/bin/chmod" "g+rw" "/run/postgresql" ]
    ];
    inherit user;
    inherit group;
    argv = [
      # ${pkgs.postgresql}/bin/initdb -D /notbackedup/postgres
      "${pkgs.postgresql}/bin/postgres" "--config-file=data/postgresql.conf"
    ];
  };

  passthru.after = [ targets.global.coldplug ];

}

