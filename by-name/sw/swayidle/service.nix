{ lib
, pkgs
, six
, targets
, sway         ? throw "you must pass swayidle a sway target"

# swaylock is not a separate s6-rc service for a few reasons: s6-rc is not
# reentrant (FIXME explain further) and we have no way to recover from `s6-rc
# start swaylock` failing (due to inability to acquire locks, etc) when called
# by swayidle.
, lock-command   ? "${pkgs.swaylock}/bin/swaylock -e -c 111111"

, user         ? sway.passthru.user
, group        ? sway.passthru.group
}:

# TODO: swaylock supports readiness notifications via `--ready-fd` -- useful?

six.mkFunnel {

  inherit user group;

  env.XDG_RUNTIME_DIR = sway.passthru.xdg-runtime-dir;
  env.WAYLAND_DISPLAY = "wayland-1";  # FIXME: why?

  # FIXME we need to set this
  #env.SWAYSOCK = "${sway.passthru.xdg-runtime-dir}/sway-ipc.${user.uid}.${sway-pid}.sock"

  run.argv = [
    "${pkgs.swayidle}/bin/swayidle"

    # after 10 minutes, turn off the screens but don't lock the console yet
    "timeout" "600" ''${pkgs.sway}/bin/swaymsg "output * power off"''
    "resume"        ''${pkgs.sway}/bin/swaymsg "output * power on"''

    # after 11 minutes, lock the console
    "timeout" "660" lock-command
  ];

   # swayidle will deparent the swaylock process (unless you use "-w", which
  # unfortunately causes swayidle to block until swaylock exits), so in order to
  # cleanly shut down swaylock by sending it SIGUSR1 we need to signal the
  # entire process group.
  #
  finish.argv = [
    # the `kill` in util-linux lets you send a signal to every process in a
    # process group; busybox doesn't seem to have this feature.
    "${pkgs.util-linux}/bin/kill"
    "-USR1"
    "--"
    "-\${4}"  # the fourth argument to a finish script is the process group
  ];

  passthru.after = [ sway ];
}
