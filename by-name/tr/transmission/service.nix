{ lib
, pkgs
, six
, host
, targets
, package ? pkgs.transmission_4
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
  ] ++ six.lib.attrsToFlags ({
    foreground     = null;
    config-dir     = "${base-dir}/config";
    watch-dir      = "${base-dir}/watch";
    download-dir   = "${base-dir}/download";
    incomplete-dir = "${base-dir}/incomplete";
  } // extra-args);

  passthru.after = [ targets.firewall ];
}

