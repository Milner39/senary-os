{ lib
, pkgs
, six
, targets
, user ? "_postgres"
, group ? "_postgres"
, data_directory ? throw "you must specify data_directory"
, extraConfig ? {}

# Attrset whose keys are usernames (from /etc/passwd) and whose values are
# postgres usernames.
, ident-file-for-local-unix-socket ? { root = "postgres"; }
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
      (lib.pipe ident-file-for-local-unix-socket [
        (lib.mapAttrsToList
          (system-username: database-username:
            "postgres-map ${system-username} ${database-username}"))
        (lib.concatStringsSep "\n")
      ]);
  } // extraConfig);
in

six.mkFunnel {

  inherit user group;

  data = {
    "postgresql.conf" = pkgs.writeText "postgres-postgresql.conf" config;
  };

  mkdir = {
    "/run/postgresql" = "0775";
  };

  run = {
    /*
    pre-argvs = [
      # TODO: do this only if the directory exists and is empty?
      #"${pkgs.doas}/bin/doas" "-u" "${user}" "${pkgs.postgresql}/bin/initdb" "-D" "${data_directory}" "-U" "_postgres"
      #"${pkgs.doas}/bin/doas" "-u" "${user}" "${pkgs.postgresql}/bin/createuser" "-s" "postgres"
      #"${pkgs.doas}/bin/doas" "-u" "${user}" "${pkgs.postgresql}/bin/createdb" "-U" "postgres" <db-name>
    ];
    */
    argv = [
      "${pkgs.postgresql}/bin/postgres" "--config-file=data/postgresql.conf"
    ];
  };

  passthru.after = [ targets.global.coldplug ];

}

