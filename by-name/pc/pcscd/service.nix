{ lib
, pkgs
, six
, targets
, extra-args ? []
, driver-paths ? []
}:

let
  plugins = pkgs.buildEnv {
    name = "pcscd-plugins";
    paths = [ "${pkgs.ccid}/pcsc/drivers" ] ++ driver-paths;
  };

  env = {
    PCSCLITE_HP_DROPDIR = "${plugins}";
  };

  run.argv = [

    "${pkgs.pcsclite}/bin/pcscd"

    "-f"  # foreground

    # bug causes mass-scanning of /etc if no configuration file
    # is provided; see https://github.com/NixOS/nixpkgs/issues/121088
    "-c" "/dev/null"

    "--disable-polkit"

  ] ++ extra-args;

in six.mkFunnel {
  inherit env run;
  passthru.after = [
    targets.global.coldplug
  ];
}
