{ lib
, pkgs
, six
, targets
, package ? pkgs.redlib
, listen-address ? "127.0.0.1"
, listen-port
, user ? "_redlib"
, group ? "_redlib"
, extraConfig ? {}
}:

let
  config = {
    SHOW_NSFW = true;
    ENABLE_RSS = true;
    LAYOUT = "clean";
    FIXED_NAVBAR = false;
    REMOVE_DEFAULT_FEEDS = true;
  } // extraConfig;

  env = {
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  } // (lib.pipe config [
    (lib.mapAttrs (k: v:
      assert lib.hasPrefix "REDLIB_" k ->
             throw "redlib extraConfig attrnames should omit the `REDLIB_` prefix";
      if lib.isBool v
      then if v then "on" else "off"
      else toString v
    ))
    (lib.mapAttrsToList (k: v:
      lib.nameValuePair "REDLIB_${k}" v))
    lib.listToAttrs
  ]);
in

six.mkFunnel {

  inherit user group;

  inherit env;

  run = {
    argv = [
      "${package}/bin/redlib"
      "-p" (toString listen-port)
    ] ++ lib.optionals (listen-address != null) [
      "-a" listen-address
    ];
  };

  passthru.after = [ targets.mdevd-coldplug ];

}
