{ lib
, pkgs
, six
, targets
, user ? "_postgres"
, group ? "_postgres"
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
    hba_file = pkgs.writeText "postgres-hba_file"
      #           database  user auth-method   auth-options
      ''
      local       all       all  peer          map=postgres-map
      '';
    ident_file = pkgs.writeText "postgres-ident_file"
      # map-name   system-username   database-username
      ''
      postgres-map root              postgres
      postgres-map _postgres         postgres
      postgres-map _bitmagnet        postgres
      '';
  } // extraConfig);
in

six.mkFunnel {

  inherit user group;

  data = {
    "postgresql.conf" = pkgs.writeText "postgres-postgresql.conf" config;
  };

  mkdir = {
    "/run/postgresql" = "0770";
  };

  run = {
    /*
    pre-argvs = [
      # TODO: do this only if the directory exists and is empty?
      #"${pkgs.doas}/bin/doas" "-u" "${user}" "${pkgs.postgresql}/bin/initdb" "-D" "${data_directory}" "-U" "postgres"
      #"${pkgs.doas}/bin/doas" "-u" "${user}" "${pkgs.postgresql}/bin/createuser" "-s" "postgres"
    ];
    */
    argv = [
      "${pkgs.postgresql}/bin/postgres" "--config-file=data/postgresql.conf"
    ];
  };

  passthru.after = [ targets.global.coldplug ];

}

