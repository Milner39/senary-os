{ lib
, pkgs
, six
, targets
, sway         ? throw "you must pass swayidle a sway target"
, lock-command ? "${pkgs.swaylock}/bin/swaylock -e -c 111111"
, user         ? sway.passthru.user
, group        ? sway.passthru.group
}:

six.mFunnel {

  run = {
    inherit user group;
    argv = [
      "${pkgs.swayidle}/bin/swayidle"

      # after 10 minutes, turn off the screens but don't lock the console yet
      "timeout" "600" (lib.escapeShellArg "swaymsg \"output * power off\"")
      "resume"        (lib.escapeShellArg "swaymsg \"output * power on\"")

      # after 11 minutes, lock the console
      "timeout" "660" (lib.escapeShellArg lock-command)
    ];
  };

  passthru.after = [ sway ];
}
