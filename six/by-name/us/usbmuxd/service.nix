{ lib
, pkgs
, six
, targets
}:

let
  pname = "usbmuxd";
in six.mkFunnel {

  # continuously copy from the system clock to the hwclock-fake file
  run =
    six.util.depot.writeExecline
      "service.${pname}.run"
      { argMode = "none"; }
      (six.util.chpst {
        argv = [
          "${pkgs.usbmuxd}/bin/usbmuxd" "-f" "-v"
        ];
      });

  passthru.after = [
    targets.mdevd
  ];

}
