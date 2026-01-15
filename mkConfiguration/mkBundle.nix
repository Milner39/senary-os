{ lib
, six
, passthru ? {}
}:
six.mkService {
  inherit passthru;
  type = "bundle";
  timeout-up = null;
  extraCommands = "";
  up = null;
  down = null;
}
