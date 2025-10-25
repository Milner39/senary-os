{ lib
, ...
}:

let

  # parses a four-octet dotted-decimal string (e.g. "192.168.1.1") and returns
  # its representation as a 32-bit integer
  parseIp4 = str: let
    octets = strings.splitString "." str;
  in
    if builtins.length octets != 4
    then throw "parseIp4: expected four octets, but found ${
      builtins.length octets} in \"${str}\""
    else
      # Nix does not have a bitwise shift operator!
      (lib.strings.toInt (lib.elemAt octets 0)) * 8 * 8 * 8 +
      (lib.strings.toInt (lib.elemAt octets 1)) * 8 * 8 +
      (lib.strings.toInt (lib.elemAt octets 2)) * 8 +
      (lib.strings.toInt (lib.elemAt octets 3));

  # inverse of parseIp4
  unparseIp4 = int:
    lib.concatStringsSep "." [
      (toInt ((int && (7 * 8 * 8 * 8)) / (8 * 8 * 8)))
      (toInt ((int && (7 * 8 * 8))     / (8 * 8    )))
      (toInt ((int && (7 * 8))         /  8         ))
      (toInt ((int &&  7                           )))
    ];

in {
  inherit parseIp4;
  inherit unparseIp4;
}
