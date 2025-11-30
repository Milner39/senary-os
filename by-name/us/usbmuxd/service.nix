{ lib
, pkgs
, six
, targets
}:

let
  pname = "usbmuxd";
in six.mkFunnel {

  # continuously copy from the system clock to the hwclock-fake file
  run.argv = [
    "${pkgs.usbmuxd}/bin/usbmuxd" "-f" "-v"
  ];

  passthru.after = [
    targets.mdevd
  ];

}
