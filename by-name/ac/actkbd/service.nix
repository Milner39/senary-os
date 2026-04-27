{ lib
, pkgs
, six
, targets

, user ? "_actkbd"
, group ? "_input"

, bindings ? {}
, device ? throw "you must specify a device"

, verbose ? false
, show-commands ? false
, show-keys ? false

  # hacks
, pre-argvs ? []
, env ? {}
}:

# TODO: parse EV_keyname so we don't have to use raw integers; in the meantime,
# `actkbd -n -s` will print these codes

# TODO: SIGHUP will reload the configuration file

# NOTE: /proc/bus/input/devices is really useful here

/*

TODO:

The supported attributes are:

- `grab': grabs the input device, blocks events from all other consumers
- `ungrab': undo `grab`
  - generally you want to do this in response to key *release* since some input
    consumers will react to a key-release even if they never see the key press
- `grabbed': ignore the binding unless the device is grabbed
- `ungrabbed': ignore the binding if the device is grabbed
- `noexec': ignore `command`; used mainly with `grab`/`ungrab`
- `exec`: on by default; specifying explicitly allows to control the ordering of
  grabbing, ungrabbing, and command execution

- `key(X)': Send a key X press event to the input layer of the system.
  - beware of event loops!!!
- `rel(X)': Send a key X release event to the input layer of the system.
- `rep(X)': Send a key X repeat event to the input layer of the system.

- `ignrel': start ignoring key-release events when calculating internal key-state
  - This allows more complex key combinations where the shortcut keys are
    pressed sequentially, rather than simultaneously. When the key combination
    is completed, the `allrel' and `rcvrel' attributes should be used to clear
    the key mask and to resume the proper reception of release events.
- `rcvrel': stop ignoring key-release events

- `set(X)': explicitly set the key-state of key X to pressed
- `unset(X)': explicitly set the key-state of key X to released
- `allrel': explicitly set the key-state of all keys to released

- `ledon(X)': Switches on the keyboard LED X.
- `ledoff(X)': Switches off the keyboard LED X.

If a key (i.e. `unset()`) is omitted, the key which triggered the event will be
used

* `not': Indicates that the current entry will match when any key except for the
  listed ones is received. This attribute can be used along with an empty
  <keys> field to match all events, regardless of the keycode.

* `all': Indicates that the current entry will match when all of the listed keys
  are pressed, without caring about the state of any other keys.

* `any': Indicates that the current entry will match when any of the listed keys
  is pressed. Not very sure what this can be used for, but it seemed nice
  to have :-)

NOTE: The `not', `all' and `any' attributes are checked in this exact order and
  if more than one have been specified, the one with the highest priority
  supersedes all others. If none of these attributes has been specified,
  then actkbd will require an exact match between the listed keys and the
  active key mask in order to execute the entry.
*/
six.mkFunnel {

  inherit user group;

  data."actkbd.conf" =
    pkgs.writeText "actkbd.conf"
      (lib.concatMapStringsSep "\n"
        ({ keys ? []
         , events ? []
         , attributes ? []
         , command
         }:
           assert lib.isList keys;
           assert lib.isList events;
           assert lib.isList attributes;
           assert lib.all lib.isInt keys;
           assert lib.all lib.isString events;
           assert lib.all (event: lib.elem event [ "key" "rep" "rel" ]) events;
           assert lib.isString command;
           lib.concatStringsSep ":" [
             (lib.concatMapStringsSep "+" toString keys)
             (lib.concatStringsSep "," events)
             (lib.concatStringsSep "," attributes)
             command
           ])
        bindings);

  env = {
  } // env;

  run.pre-argvs = [
    # ensure device is grouped to the input group (FIXME: this should already be true)
    [ "${pkgs.busybox}/bin/chgrp" group device ]
  ] ++ pre-argvs;

  run.argv = [
    "${pkgs.actkbd}/bin/actkbd"
    "-c" "data/actkbd.conf"
    "-d" device
  ] ++ lib.optionals verbose [
    "-v"
  ] ++ lib.optionals show-commands [
    "-x"
  ] ++ lib.optionals show-keys [
    "-s"
  ];

  passthru.after = [ targets.global.coldplug ];
}
