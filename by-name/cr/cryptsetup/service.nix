{ lib
, six
, pkgs
, targets

# TODO: infer device-label from sname?  Like `targets.blockdev.nvme1-decrypted` => `nvme1-decrypted`
, device-label ? null
, device ? if device-label == null then throw "you must specify device or device-label" else "/dev/disk/by-label/${device-label}"
, key-file
, name ? if device-label == null then throw "you must specify name or device-label" else "${device-label}-decrypted"
, allow-discards ? true
}:

six.mkOneshot {

  up = six.util.execline.ifthenelse {
    cond = six.util.execline.discard-stdout [
      "${pkgs.cryptsetup}/bin/cryptsetup"
      "status"
      name
    ];
    no = [
      "${pkgs.cryptsetup}/bin/cryptsetup"
      "luksOpen"
      "--key-file" key-file
      device
      name
    ] ++ lib.optionals allow-discards [
      "--allow-discards"
    ];
  };

  down = six.util.execline.ignore-exit-code [
    "${pkgs.cryptsetup}/bin/cryptsetup"
    "luksClose"
    name
  ];

  passthru.after = [
    # FIXME need to be after the underlying device
    targets.mounts.proc
    targets.mounts.sys
    targets.global.coldplug
  ];

}
