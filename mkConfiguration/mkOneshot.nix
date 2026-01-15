{ lib
, six
, timeout-up ? null   # milliseconds
, up   ? null
, down ? null
, passthru ? {}
}:
six.mkService {
  inherit timeout-up passthru up down;
  type = "oneshot";
  extraCommands = "";
}
