{ lib
, stdenv
, pkgs
, alsaSupport ? !stdenv.hostPlatform.isMips
, modprobe-command ? "/run/current-system/boot/modprobe-wrapped"
, host

# This is a list of attrsets, each of which will be passed to mkMdevConfLine
, extraStructuredConfig

# mdevd events will be logged to this file; set to `null` to disable logging
, event-log-file ? "/run/mdevd-events.log"
}:

let
  helpers = import ./helpers.nix
    { inherit lib stdenv pkgs alsaSupport; };

  busybox = "${pkgs.busybox}/bin/busybox ";

  mkMdevConfLine =
    { stop-if-match ? true,
      user ? "root",
      group ? "root",
      octal-mode ? "660",

      devname-regex ? ".*",
      env-regexes ? {},

      create-device-node ? true,
      symlink-device-node ? false,   # if false then move rather than symlink
      path ? null,

      remove-argv ? null,
      add-argv ? null,
      change-argv ? null,

      use-execline ? false,
  }:
    assert lib.isString octal-mode;
    assert !(builtins.hasAttr user host.users) ->
            throw "mdev.conf mentions user ${user} which is not in host.users";
    assert !(builtins.hasAttr group host.groups) ->
            throw "mdev.conf mentions group ${group} which is not in host.groups";

    assert (devname-regex==null && env-regexes=={}) ->
           throw "you must specify either devname-regex or env-regexes";
    assert
      (if remove-argv==null then 0 else 1) +
      (if change-argv==null then 0 else 1) +
      (if add-argv==null then 0 else 1)
      > 1 -> throw "at most one of {add,change,remove}-argv must be specified";

    let

      conditions =
        # There is a third type of condition supported by mdevd, "@maj,min[-min2]"
        # which is not supported here.  You can simulate it using environment
        # regexes.
        lib.mapAttrsToList (varname: regex: "${varname}=${regex}") env-regexes ++
        lib.optionals (devname-regex!=null) [ devname-regex ];

      device-node-action =
        if !create-device-node
        then "!"
        else if path == null
        then ""
        else if symlink-device-node
        then ">${path}"
        else "=${path}";

      argv-prefix =
        if use-execline
        then
          # FIXME: must ensure that `execline` is reachable via $PATH
          if change-argv!=null then "&"
          else if remove-argv!=null then "-"
          else if add-argv!=null then "+"
          else ""
        else
          if change-argv!=null then "*"
          else if remove-argv!=null then "$"
          else if add-argv!=null then "@"
          else "";

      argv' =
        if change-argv!=null then change-argv
        else if remove-argv!= null then remove-argv
        else if add-argv!=null then add-argv
        else [];
    in

      # These checks are very important.  Mdevd will refuse to start up if any
      # user or group mentioned in mdev.conf is missing from
      # /etc/{passwd,group}; these checks are done immediately at startup rather
      # than lazily when the device is connected.  Almost every target depends
      # on mdevd, so the result is a bricked system.
      assert !host.users?${user} ->
              throw ''mdevd.conf references user "${user}" which does not appear in host.users'';
      assert !host.groups?${group} ->
              throw ''mdevd.conf references user "${group}" which does not appear in host.users'';

      # Syntax:
      # [-]devicename_regex user:group mode [=path]|[>path]|[!] [@|$|*cmd args...]
      # [-]$ENVVAR=regex    user:group mode [=path]|[>path]|[!] [@|$|*cmd args...]
      # [-]@maj,min[-min2]  user:group mode [=path]|[>path]|[!] [@|$|*cmd args...]
      #
      # [-]: do not stop on this match, continue reading mdev.conf
      # =: move, >: move and create a symlink
      # !: do not create device node
      # @|$|*: run cmd if $ACTION=remove, @cmd if $ACTION=add, *cmd in all cases
      lib.concatStringsSep " " [
        (lib.optionalString (!stop-if-match) "-" + (lib.concatStringsSep ";" conditions))
        "${user}:${group}"
        octal-mode
        device-node-action
        (argv-prefix + (lib.concatStringsSep " " argv'))
      ];
in
# Based on the example mdev.conf from mdev-like-a-boss
  lib.pipe (
    [
    ] ++ lib.optionals (event-log-file != null) [
      # log each event to /run/mdevd-events.log
    {
      stop-if-match = false;
      create-device-node = false;
      devname-regex = ".*";
      path = null;
      change-argv = [
        "(${lib.concatStringsSep "; " [
          "unset TZ"
          "unset EXECLINE_STRICT"
          "echo -n $ACTION \" \"" "unset ACTION"
          "echo -n $SEQNUM \" \"" "unset SEQNUM"
          "${busybox} env | ${busybox} grep -v \"^\\(_\\|SHLVL\\|PATH\\|PWD\\)=\" | ${busybox} sort | ${busybox} tr \"\\n\" \" \" "
          "echo"
        ]}) >> ${event-log-file}"
      ];
    }
    ] ++ [

    # /dev/serial/by-id
    {
      stop-if-match = false;
      env-regexes.SUBSYSTEM = "usb-serial";
      add-argv = [
        (pkgs.writeScript "mdevd-add-serial-by-id" ''
          #!${pkgs.runtimeShell}
          PATH=${lib.makeBinPath [ pkgs.busybox ]}
          MDEV=$(basename $DEVPATH)
          DP0=/sys/$DEVPATH
          DP1=$(dirname "$DP0")
          DP=$(dirname "$DP1")
          if [[ -e "$DP/serial" ]]; then
            SERIAL=$(cat "$DP/serial" | tr ' ' '_')
            PRODUCT=$(cat "$DP/product" | tr ' ' '_')
            MANUFACTURER=$(cat "$DP/manufacturer" | tr ' ' '_')
            IFACE=$(cat "$DP1/bInterfaceNumber" | tr ' ' '_')
            BUS="usb"
            PORT=0  # FIXME
            mkdir -p /dev/serial/by-id
            ln -sf ../../"$MDEV" "/dev/serial/by-id/''${BUS}-''${MANUFACTURER}_''${PRODUCT}_''${SERIAL}-if''${IFACE}-port''${PORT}"
          fi
        '')
        "$MDEV"
      ];
    }

    # support module loading on hotplug
    {
      devname-regex = null;
      env-regexes = { "$MODALIAS" = ".*"; };
      add-argv = [ modprobe-command "\"$MODALIAS\"" ];
      path = null;
    }

    # /dev/null may already exist; therefore ownership has to be changed with command
    {
      devname-regex = "null";
      octal-mode = "666";
      add-argv = [ busybox "chmod" "666" "$MDEV" ];
    }
    { devname-regex = "zero"; octal-mode = "666"; }
    { devname-regex = "full"; octal-mode = "666"; }
    { devname-regex = "random"; octal-mode = "444"; }
    { devname-regex = "urandom"; octal-mode = "444"; }
    { devname-regex = "hwrandom"; octal-mode = "444"; }
    { devname-regex = "grsec"; }

    # Kernel-based Virtual Machine.
    { devname-regex = "kvm"; }

    # vhost-net, to be used with kvm.
    { devname-regex = "vhost-net"; }

    { devname-regex = "kmem"; octal-mode = "640"; }
    { devname-regex = "mem"; octal-mode = "640"; }
    { devname-regex = "port"; octal-mode = "640"; }
    # console may already exist; therefore ownership has to be changed with command
    {
      devname-regex = "console";
      octal-mode = "600";
      add-argv = [ busybox "chmod" "600" "$MDEV" ];
    }
    { devname-regex = "ptmx"; octal-mode = "666"; }
    { devname-regex = "pty.*"; }

    # Typical devices
    { devname-regex = "tty"; octal-mode = "666"; }
    { devname-regex = "tty[0-9]*"; }
    { devname-regex = "vcsa*[0-9]*"; }
    { devname-regex = "ttyS[0-9]*"; }

    # block devices
    { devname-regex = "ram([0-9]*)"; octal-mode = "660"; symlink-device-node = true; path = "rd/%1"; }
    { devname-regex = "loop([0-9]+)"; octal-mode = "660"; symlink-device-node = true; path = "loop/%1"; }
    {
      devname-regex = "sr[0-9]*";
      octal-mode = "660";
      add-argv = [ busybox "ln" "-sf" "$MDEV" "cdrom" ];
    }
    { devname-regex = "fd[0-9]*"; }
    {
      env-regexes = { SUBSYSTEM = "block"; };
      octal-mode = "660";
      change-argv = [ "${helpers}/bin/storage-device" ];
    }

    # Run settle-nics every time new NIC appear.
    # If you don't want to auto-populate /etc/mactab with NICs, run 'settle-nis' without '--write-mactab' param.
    #-SUBSYSTEM=net;DEVPATH=.*/net/.*;.*     root:root 600 @${helpers}/bin/settle-nics --write-mactab

    { devname-regex = "net/tun[0-9]*"; }
    { devname-regex = "net/tap[0-9]*"; octal-mode = "600"; }

  ] ++ lib.optionals alsaSupport [
    # alsa sound devices and audio stuff
    {
      env-regexes = { SUBSYSTEM = "sound"; };
      group = "audio";
      octal-mode = "660";

      # Disabled because most of what this script does is mute the mixers (and
      # leave them muted), which is very frustrating for the user who then needs
      # to figure out why no sound is coming out of their machine... all to avoid
      # "Dragonfly Red 1.07 blasting at full volume"
      #
      #add-argv = [ "${helpers}/bin/sound-control" ];
    }

  ] ++ (lib.map (devname-regex: {
    inherit devname-regex;
    group = "audio";
    octal-mode = "660";
    path = "sound/";
    symlink-device-node = true;
  }) [
    "adsp"
    "audio"
    "dsp"
    "mixer"
    "sequencer.*"
  ]) ++ [

    # raid controllers
    { devname-regex = "cciss!(.*)"; path = "cciss/%1"; }
    { devname-regex = "ida!(.*)"; path = "ida/%1"; }
    { devname-regex = "rd!(.*)"; path = "rd/%1"; }

    { devname-regex = "fuse"; octal-mode = "666"; }

    { devname-regex = "card[0-9]"; group = "video"; path = "dri/"; }
    { devname-regex = "dri/.*"; group = "video"; }

    { devname-regex = "agpgart"; path = "misc/"; symlink-device-node = true; }
    { devname-regex = "psaux"; path = "misc/"; symlink-device-node = true; }
    { devname-regex = "rtc"; octal-mode = "664"; path = "misc/"; symlink-device-node = true; }

    # input stuff
    { env-regexes.SUBSYSTEM = "input"; }

    # v4l stuff
    { devname-regex = "vbi[0-9]"; group = "video"; path = "v4l/"; symlink-device-node = true; }
    { devname-regex = "video[0-9]"; group = "video"; path = "v4l/"; symlink-device-node = true; }

    # dvb stuff
    { devname-regex = "dvb.*"; group = "video"; }

    # Don't create old usbdev* devices.
    { devname-regex = "usbdev[0-9].[0-9]*"; create-device-node = false; }

    # Stop creating x:x:x:x which looks like /dev/dm-*
    { devname-regex = "[0-9]+\\:[0-9]+\\:[0-9]+\\:[0-9]+"; create-device-node = false; }

    # /dev/cpu support.
    { devname-regex = "microcode"; octal-mode = "600"; path = "cpu/"; }
    { devname-regex = "cpu([0-9]+)"; octal-mode = "600"; path = "cpu/%1/cpuid"; }
    { devname-regex = "msr([0-9]+)"; octal-mode = "600"; path = "cpu/%1/msr"; }

    # Populate /dev/bus/usb.
    {
      stop-if-match = false;
      env-regexes = {
        SUBSYSTEM = "usb";
        DEVTYPE = "usb_device";
      };
      octal-mode = "660";
      change-argv = [ "${helpers}/bin/dev-bus-usb" ];
    }

  ] ++ extraStructuredConfig ++ [

    # Catch-all other devices, Right now useful only for debuging.
    #.* root:root 660 *${helpers}/bin/catch-all
  ]) [
    (lib.map mkMdevConfLine)
    (lib.concatStringsSep "\n")
    (pkgs.writeText "mdevd-conf")
  ]

