{ lib
, pkgs
, six
, targets
, host
, seatd        ? throw "you must pass sway a seatd target"
, user         ? throw "username under which to run sway"
, group
, extra-groups ? []
, tty-dev      ? throw "the /dev/tty* device on which to run sway"
, sway-config  ? throw "path to the sway configuration file"
, sway-args    ? [ ]  # extra command line arguments for sway
, sway-env     ? { }  # extra environment variables to set

}@args:

let

  run-user-dir = "/run/user/${toString host.users.${user}.uid}";
  xdg-runtime-dir = "${run-user-dir}/xdg";

#'' + lib.optionalString (env ? WLR_RENDER_DRM_DEVICE) ''
#  test -e ${env.WLR_RENDER_DRM_DEVICE} || \
#    (echo "${env.WLR_RENDER_DRM_DEVICE} does not exist yet; will retry"; exit -1)

in
six.mkFunnel {
  inherit user group extra-groups;
  mkdir = {
    ${run-user-dir} = "0700";
    ${xdg-runtime-dir} = "0700";
  };
  env = {
    # this directory is not freely chosen; nixpkgs hardwires the string
    # below into the RPATHs of several libraries, and configure/meson
    # flags of several packages.
    MESA_DRIVERS_PATH = "/run/opengl-driver";
    XDG_RUNTIME_DIR = xdg-runtime-dir;
    HOME = "${host.users.${user}.home-directory}";
    PATH = "/run/current-system/sw/bin";
  } // sway-env;
  run.chdir = host.users.${user}.home-directory;
  run.redirect-stdin-from = tty-dev;
  run.argv = [
    "${pkgs.sway}/bin/sway"
  ] ++ sway-args ++ [
    "-c" "${sway-config}"
  ];

  passthru = {
    after = [ targets.global.coldplug seatd ];
    essential = true;
  };
}

# TODO
# - `nice -n -19 ionice -c Realtime` -- but this isn't right because child processes inherit the elevated priority

# useful variables
#export WLR_LIBINPUT_NO_DEVICES=1     # start even if no input devices
#export WLR_DIRECT_TTY=/dev/tty1
#export WLR_RENDERER=gles2
#export LIBGL_DEBUG=1
#export EGL_PLATFORM=gbm
#export EGL_LOG_LEVEL=debug
#export WLR_BACKENDS=libinput,drm
#export WLR_NO_HARDWARE_CURSORS=1
#export WLR_DRM_DEVICES=/dev/dri/card0
#export WLR_RENDERER_ALLOW_SOFTWARE=1
#export MESA_LOADER_DRIVER_OVERRIDE=radeon
#export MESA_DEBUG=1
#export SWAY_ARGS="-d $SWAY_ARGS"
#export SWAY_ARGS=-V
#export SWAY_ARGS="-Dnoatomic"
#export SWAY_ARGS="-Dnoscanout"
#export WLR_RDP_TLS_CERT_PATH=/home/user/sway/tls.crt
#export WLR_RDP_TLS_KEY_PATH=/home/user/sway/tls.key
#export WLR_DRM_NO_ATOMIC=1
#export WLR_DRM_NO_MODIFIERS=1
#export EGL_PLATFORM=gbm
#export MESA_GL_VERSION_OVERRIDE=3.3
#export MESA_GLSL_VERSION_OVERRIDE=330
