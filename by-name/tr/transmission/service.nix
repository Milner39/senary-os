{ lib
, pkgs
, six
, host
, targets
, package ? pkgs.transmission
, user ? "_transmission"
, group ? "_transmission"
, base-dir ? "/var/service/transmission"
, extra-args ? {}
}:

let

in six.mkFunnel {

  inherit user;
  inherit group;

  mkdir = {
    "${base-dir}" = "0700";
    "${base-dir}/config" = "0700";
    "${base-dir}/watch" = "0700";
    "${base-dir}/download" = "0700";
    "${base-dir}/incomplete" = "0700";
  };

  env.CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  run.argv = [
    "${package}/bin/transmission-daemon"
    "--foreground"
    "--config-dir"     "${base-dir}/config"
    "--watch-dir"      "${base-dir}/watch"
    "--download-dir"   "${base-dir}/download"
    "--incomplete-dir" "${base-dir}/incomplete"
  ] ++ lib.pipe extra-args [
    (lib.mapAttrsToList
      (key: val:
        "--${key}=${lib.escapeShellArg (six.lib.toString val)}"))
  ];

  passthru = {
    after = [ targets.firewall ];
  };
}

