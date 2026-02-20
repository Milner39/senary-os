{ lib
, pkgs
, six
, targets
}:

# There are two ways a profile can become activated:
#
# 1. It can be the `nextboot` profile at boot time
# 2. By running $configuration/bin/activate on an already-running system
#
# In case 2, the activation script will update /nix/var/nix/profiles/activated;
# it can do this because the root filesystem is already mounted read-write.
#
# In case 1, the root filesystem is mounted read-only at the time the activation
# script runs; it will not be remounted read-write until much later.  This
# oneshot waits until root is remounted read-write and then performs the task of
# updating /nix/var/nix/profiles/activated.
#
six.mkOneshot {

  # FIXME: dereference the /run/current-system symlink; if we don't, nix will
  # try to hit the substituters for it
  up = [
    "${pkgs.nix}/bin/nix-env"
    "-p" "/nix/var/nix/profiles/activated"
    "--set" "/run/current-system" # nix will dereference this symbolic link for us
  ];

  passthru.after = [
    # root must be read-write
    targets.mounts.""
  ];

}
