{ lib
, yants
, sixos
, ...
}:

# local args
{ s6-fdholder-daemon-username ? null   # -h
, verbosity                   ? 3      # -v
, default-runlevel            ? "default"

# This directory can only be changed by doing a reboot or pivot_root(), since it
# is passed to s6-supervise (which is forked only at boot or pivot_root() time).
# Any references to it should be via `/run/booted-system/six/scandir`, and never
# via `/run/current-system`. (why?  I can't remember...)
, scandir                     ? "/run/service"

# This mainly protects against recursive invocations of s6-rc tools.  Recursive
# invocations are a bug, which should fail rather than deadlock.
, fail-on-lock-contention     ? true   # -b

, nixpkgs-version ? "unknown-nixpkgs-version"
}:

host-final:
host-prev:

let

  # FIXME: use s6-ln here for atomicity
  # during initial activation, creates a symlink from `/${path}` to `/run/current-system/${path}`
  linkify = path:
    let path' = lib.removePrefix "/" path; in
    linkify-to-from "/run/current-system/${path'}" path';

  linkify-to-from = to-path: from-path:
    linkify-cond-to-from "! -e /${from-path}" to-path from-path;

  linkify-cond-to-from = cond: to-path: from-path:
    let from-path' = lib.removePrefix "/" from-path; in
  ''
    if [[ ${cond} ]]; then
      ${pkgs.busybox}/bin/busybox ln -sfT ${to-path}  $RWMOUNT/${from-path'}
    fi'';

  inherit (host-final) pkgs boot;
  sw =
    if host-final.sw != null
    then host-final.sw
    else pkgs.buildEnv {
      name = "sixos-sw";
      paths = with pkgs; [
        # these are the hard dependencies of sixos, so we might as well include
        # them in the default $PATH
        busybox
        s6
        s6-rc
        doas
        nix
      ];
    };

  delete-generations = host-final.delete-generations or null;

  # FIXME(amjoseph): do the same abduco trick here that we already do in the initrd
  # FIXME(amjoseph): should be using boot.initrd.ttys instead of boot.kernel.console here
  early-getty = lib.concatStringsSep " " [
    "${pkgs.busybox}/bin/getty"
    "-nl"
    "${pkgs.busybox}/bin/sh"
    "${toString (boot.kernel.console.baud or 115200)}"
    "${boot.kernel.console.device or "tty0"}"
  ];

  # note: add-spaths must be the last extension before
  # "convert-before-to-after", to be sure that it is able to "see" any
  # additional services added by earlier overlays
  sorted-collected-targets = lib.pipe host-final [
    (host: (lib.mapAttrsToList (_: v: v) (sixos.lib.extractDerivations host.targets)))
    (lib.filter (v: v?passthru.spath))
    (map (s: lib.nameValuePair (lib.concatStringsSep "." s.spath) s))
    lib.listToAttrs
    lib.attrValues
    (lib.sort (a: b: (lib.concatStringsSep "." a.passthru.spath) < (lib.concatStringsSep "." b.passthru.spath)))
  ];

  source = pkgs.runCommand "s6-rc-source" { preferLocalBuild = true; } (''
    mkdir -p $out
    ${lib.concatMapStrings (target:
      # This is tricky; we want just the right level of symlink-following here
      # to maximize sharing within /nix/store, but also ensure that at
      # activation time /run/service/*/data isn't a symlink to the store
      ''
      mkdir -p                  $out/${lib.concatStringsSep "." target.passthru.spath}
      cp -a ${target.outPath}/* $out/${lib.concatStringsSep "." target.passthru.spath}/
      chmod u+w ${target.outPath}/* || true
      '')
      sorted-collected-targets}
    ${lib.concatMapStrings (target:
      # s6-rc requires that consumers reference their producers and vice-versa;
      # when mapping services to derivations this would create cyclic
      # derivations, which are disallowed.  Therefore, the per-service
      # derivations include only the `producer-for` entry.  Links in the reverse
      # direction (i.e. `consumer-for`) are created just before invoking
      # s6-rc-compile.
      ''
      if [ -e "${target.outPath}/producer-for" ]; then
        echo ${lib.concatStringsSep "." target.passthru.spath} >> $out/$(cat ${target.outPath}/producer-for)/consumer-for
      fi
      '')
      sorted-collected-targets}
  '');

  compiled = pkgs.runCommand "s6-rc-compiled" { preferLocalBuild = true; } (''
    mkdir -p $out/six/s6-rc
    ln -s ${source} $out/six/s6-rc/source
    ${pkgs.pkgsBuildTarget.s6-rc}/bin/s6-rc-compile ${lib.escapeShellArgs
      (lib.optionals (verbosity!=null) [
        "-v" (toString verbosity)
      ] ++ lib.optionals (s6-fdholder-daemon-username != null) [
        "-h" s6-fdholder-daemon-username
      ])} $out/six/s6-rc/db ${source}
  '');

  s6-linux-init-cpio = (pkgs.callPackage ./s6-linux-init.nix { }).override {
    inherit early-getty;
    initial-path = "/run/current-system/sw/bin";
  };

  # We need to provide the kernel (via /proc/sys/kernel/modprobe) the path to a
  # single executable that it can spawn, *without additional arguments* in
  # order to load modules.  Since we (a) want to respect the user's blacklists
  # and (b) keep modules in a non-FHS location we need to pass a flag to
  # modprobe to tell it where the modules are.  We don't want the wrapped
  # version of modprobe to "occlude" the ordinary one in the user's $PATH, so
  # we put it in /boot and give it a different name (the user can link it into
  # their $PATH with the name modprobe if desired).
  #
  # Note that this command is invoked via the /run/current-system link, but
  # searches for modules in /run/booted-system.  Activating a new configuration
  # will use the new configuration's modprobe binary, but it will still take
  # kernel modules from whatever configuration was booted.
  #
  # Busybox is used here because kmod randomly decides to ignore module
  # blacklisting, and I'm sick of debugging it.  Busybox modprobe just works
  # properly the first time.
  #
  modprobe-wrapped = pkgs.writeScriptBin "modprobe-wrapped" ''
    #!${pkgs.busybox}/bin/sh
    ${pkgs.busybox}/bin/modprobe -b -d /run/booted-system/kernel-modules "$@"
  '';

  mkBootDir =
    # systems these days need so much firmware that most machines are likely to
    # fail to boot if the firmware directory is missing.  if you really really
    # want a no-firmware boot, pass the empty directory.
    let
      firmware =
        if lib.isList boot.kernel.firmware
        then pkgs.buildEnv {
          name = "firmware";
          paths = lib.pipe boot.kernel.firmware [
            #(lib.map toString)
            #lib.naturalSort   # for normalization purposes
          ];
        }
        else boot.kernel.firmware;
    in
   ''
     mkdir -p $out/boot
     ln -sT ${boot.kernel.payload} $out/boot/kernel
   '' + lib.optionalString (boot.kernel.modules != null) ''
     ln -sT ${boot.kernel.modules} $out/boot/kernel-modules
     # path has to match NixOS in order to use the nixpkgs depmod/insmod/modprobe tools :(
     ln -sT boot/kernel-modules $out/kernel-modules
   '' + lib.optionalString (boot?initrd.image) ''
     ln -sT ${boot.initrd.image} $out/boot/initrd
   '' + lib.optionalString (boot?kernel.dtb) ''
     ln -sT ${boot.kernel.dtb} $out/boot/dtb
   '' + lib.optionalString (boot?spec) ''
     ln -sT ${boot.spec} $out/boot/boot.json
   '' +
   # six places `init` in $out/boot rather than $out/bin because there is no
   # scenario in which this script should ever be accessible via a user's $PATH.
   ''
     ln -sT ${s6-linux-init-cpio}/boot/init $out/boot/init
     echo ${lib.concatStringsSep " "
       (map lib.escapeShellArg boot.kernel.params ++ [
         "init=$out/boot/init"
         "configuration=$out"
       ])} > $out/boot/kernel-params
   '' +
   # somewhat-similarly for modprobe-wrapped; we need to be able to reference
   # it, and so does the kernel, but the user might not want this in their $PATH
   ''
     cp -a ${modprobe-wrapped}/bin/modprobe-wrapped $out/boot/modprobe-wrapped
   '' + lib.optionalString (firmware == null) ''
     mkdir -p $out/boot/firmware
   '' + lib.optionalString (firmware != null) ''
     ln -sT ${firmware} $out/boot/firmware
   '' + ''
     ln -sT boot/firmware $out/firmware    # to match NixOS path burned-in to nixpkgs
   '';

  # We will symlink from `$out/${name}` to `${value}` for each of these.
  extra-links = {
    "six/s6-rc/source" = source;
    "six/s6-rc/db" = "${compiled}/six/s6-rc/db";
    "six/scandir" = scandir;
    "etc/passwd" =
      pkgs.writeText "etc-passwd" (sixos.mkHost.users.mkEtcPasswd {
        inherit (host-final) pkgs users groups;
      });
    "etc/group" =
      pkgs.writeText "etc-group" (sixos.mkHost.users.mkEtcGroup {
        inherit (host-final) users groups;
      });
    "etc/services" = "${pkgs.iana-etc}/etc/services";
    "etc/protocols" = "${pkgs.iana-etc}/etc/protocols";
    "etc/hosts" =
      pkgs.writeText "etc-hosts" (lib.pipe host-final.etc.hosts [
        (lib.mapAttrsToList (key: val: ''
            ${key} ${lib.concatStringsSep " " val}
          ''))
        lib.concatStrings
      ]);
    "etc/doas.conf" =
      pkgs.writeText "etc-doas-conf"
        # Warning!  `doas` *requires* a trailing newline!
        (lib.pipe host-final.doas-conf [
          (map (line: line + "\n"))
          lib.concatStrings
        ]);
  } // lib.optionalAttrs (host-final?etc.iproute2) {
    "etc/iproute2/rt_tables" =
      pkgs.writeText "etc-iproute2" (lib.pipe host-final.etc.iproute2.rt_tables [
        (lib.mapAttrsToList
          (table-name: table-number:
            "${toString table-number} ${table-name}"))
        (lib.concatStringsSep "\n")
      ]);
  };

  configuration = (pkgs.runCommand "six-system-${host-final.name}-${nixpkgs-version}" { preferLocalBuild = true; } (''
    mkdir -p $out
    mkdir -p $out/six/s6-rc
    mkdir -p $out/bin
    mkdir -p $out/etc

    ${pkgs.gnu-config}/config.sub "${pkgs.hostPlatform.config}" > $out/system-canonical-gnu-triple

    ${lib.pipe
      (extra-links // host-final.extra-configuration-links) [
        (lib.mapAttrsToList (link-name: link-path: ''
          mkdir -p $out/${builtins.dirOf link-name}
          ln -s ${link-path} $out/${link-name}
        ''))
        lib.concatStrings
      ]
    }

    cat > $out/bin/activate<<\EOF
    #!${pkgs.runtimeShell} -e
  ''
    # save the old wrapped /run/six/bin/doas; by getting to this point we know
    # that either it works or else that the user doesn't need it to invoke
    # activation scripts (i.e. can log in directly as root).  We use
    # /nix/var/nix/profiles/activated instead of /run/current-system so this
    # works both on first-bootup as well as configuration-switch.
    #
    # FIXME: should probably wrap these instead of copying them
    #
    # FIXME: this still allows a broken doas.conf to footgun everything because
    # doas.previous will still follow the symlink from /etc/doas.conf to
    # /run/current-system/etc/doas.conf
    #
    # FIXME: should run `doas -C` to validate the doas.conf as a sanity check.
  + ''
    ${pkgs.busybox}/bin/mkdir -p /run/six/bin
    if [[ -e /nix/var/nix/profiles/activated/bin/doas.unwrapped ]]; then
      ${pkgs.busybox}/bin/cp /nix/var/nix/profiles/activated/bin/doas.unwrapped /run/six/bin/doas.previous
      ${pkgs.busybox}/bin/chmod 4755 /run/six/bin/doas.previous
    fi
    ${pkgs.busybox}/bin/cp ${builtins.placeholder "out"}/bin/doas.unwrapped /run/six/bin/doas
    ${pkgs.busybox}/bin/chmod 4755 /run/six/bin/doas

    if [[ -d /run/s6-rc ]]; then
      # s6-svscan is already up and running; switch to the new configuration
      ${pkgs.s6-rc}/bin/s6-rc-update -v 8 $@ ${compiled}/six/s6-rc/db

      # s6-ln is used because POSIX ln is defined such that it cannot be atomic.
      ${pkgs.s6-portable-utils}/bin/s6-ln -sfn ${builtins.placeholder "out"} /run/current-system
      ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/activated --set ${builtins.placeholder "out"}
    else
      # first activation after a new bootup
      ${pkgs.busybox}/bin/ln -sfT /run/current-system/sw /run/opengl-driver
  '' +
# TODO (from nixos): mkdir -m 1777 /var/tmp
  ''
      # root filesystem is not yet initialized
      if [[ ! -e /etc/passwd && ! -L /etc/passwd ]]; then
  '' + ''

        # We don't want to remount / read-write, so instead we bind-mount it and
        # remount *that* as read-write.  To do so, we need an empty directory,
        # preferably outside /nix/store.  We use /nix/var/nix/profiles/per-user
        # since `nix copy` will create it.
        RWMOUNT=/nix/var/nix/profiles/per-user

        ${pkgs.busybox}/bin/mount --bind / $RWMOUNT
        ${pkgs.busybox}/bin/mount -o remount,rw / $RWMOUNT
        ${pkgs.busybox}/bin/mkdir -m 0555 -p $RWMOUNT/etc
        ${pkgs.busybox}/bin/mkdir -m 0700 -p $RWMOUNT/etc/secrets
        ${pkgs.busybox}/bin/mkdir -m 0555 -p $RWMOUNT/bin
        ${pkgs.busybox}/bin/mkdir -m 0555 -p $RWMOUNT/usr/bin
        ${linkify "/bin/sh"}
        ${linkify-cond-to-from
          ''"$(${pkgs.busybox}/bin/readlink /bin/sh)" != "/run/current-system/sw/bin/sh"''
          "/run/current-system/sw/bin/sh"
          "/bin/sh"}
        ${linkify-cond-to-from
          ''"$(${pkgs.busybox}/bin/readlink /usr/bin/env)" != "/run/current-system/sw/bin/env"''
          "/run/current-system/sw/bin/env"
          "/usr/bin/env"}
        ${linkify "/etc/passwd"}
        ${linkify "/etc/group"}
        ${linkify "/etc/services"}
        ${linkify "/etc/protocols"}
        ${linkify "/etc/hosts"}
        ${linkify "/etc/doas.conf"}
        ${linkify "/etc/profile"}
  '' + lib.optionalString (host-final?iproute) ''
        ${linkify "/etc/iproute2"}
  '' + ''
        ${pkgs.busybox}/bin/mkdir -p $RWMOUNT/tmp
        ${pkgs.busybox}/bin/mkdir -p $RWMOUNT/sys
        ${pkgs.busybox}/bin/mkdir -p $RWMOUNT/dev
        ${pkgs.busybox}/bin/mkdir -p $RWMOUNT/proc
        ${pkgs.busybox}/bin/mkdir -p $RWMOUNT/run

        ${pkgs.busybox}/bin/mkdir -p $RWMOUNT/var/empty
        ${pkgs.busybox}/bin/chmod 0555 $RWMOUNT/var/empty
        ${pkgs.busybox}/bin/chown 0:0 $RWMOUNT/var/empty
        ${pkgs.e2fsprogs}/bin/chattr -f +i $RWMOUNT/var/empty

        ${pkgs.busybox}/bin/umount $RWMOUNT
      fi

      ${pkgs.busybox}/bin/ln -sfn ${builtins.placeholder "out"} /run/booted-system
      ${pkgs.busybox}/bin/ln -sfn ${builtins.placeholder "out"} /run/current-system

      # ectool (and other things) expect /run/lock (formerly /var/lock) to exist
      ${pkgs.busybox}/bin/mkdir /run/lock

      ${pkgs.busybox}/bin/mkdir -p ${scandir}
      ${pkgs.s6-rc}/bin/s6-rc-init -d -c /run/current-system/six/s6-rc/db $@ ${scandir}
      # Presumably / is still read-only at this point, so we don't try to
      # `nix-env --set` the `activated` profile.  The `nextboot` profile was
      # updated prior to reboot, so you can reconstruct the full activation
      # history by interleaving it with `activated`.
      exec ${pkgs.s6-rc}/bin/s6-rc -v2 -up change ${default-runlevel}
    fi
    EOF

    cat > $out/bin/dry-activate<<\EOF
    #!${pkgs.runtimeShell} -ex
    exec ${pkgs.s6-rc}/bin/s6-rc-update -n $@ -v 8 ${builtins.placeholder "out"}/six/s6-rc/db
    EOF

    cat > $out/bin/kexec-load <<\EOF
    #!${pkgs.runtimeShell} -ex
    ${pkgs.busybox}/bin/busybox mkdir -p /run/kexec
    ${pkgs.busybox}/bin/busybox chmod 0700 /run/kexec
    ${pkgs.busybox}/bin/busybox cp ${boot.initrd.image} /run/kexec/initrd
  ''

  # FIXME(amjoseph): provide a more general "copy these files into the initrd
  # when kexec()ing" instead of this gross hack
  + ''
    if [[ -e /etc/miniboot-cryptsetup-keyfile ]]; then
      echo miniboot-cryptsetup-keyfile | ${pkgs.cpio}/bin/cpio --create --append -O /run/kexec/initrd -H newc -D /etc
    fi
  ''

  + ''
    ${pkgs.kexec-tools}/bin/kexec ${lib.escapeShellArgs ([
      "--load"
    ] ++ lib.optionals (boot?initrd.image) [
      "--initrd=/run/kexec/initrd"
    ] ++ lib.optionals (boot?kernel.dtb) [
      "--dtb=${boot.kernel.dtb}"
    ])} --command-line=${
      lib.pipe (
        boot.kernel.params ++ [
          "configuration=${builtins.placeholder "out"}"
        ]) [
          (lib.concatStringsSep " ")
          lib.escapeShellArg
        ]
    } ${boot.kernel.payload}
    rm -f /run/kexec/initrd

    ${pkgs.busybox}/bin/sync
    ${pkgs.busybox}/bin/sleep 1
    EOF

    cat > $out/bin/kexec <<EOF
    #!${pkgs.runtimeShell} -ex
    $out/bin/kexec-load
    ${pkgs.kexec-tools}/bin/kexec -e
    EOF

  ''
    # need WAY more sanity checks at the time nextboot is executed, especially
    # when installing for the first time using a chroot:
    # - all mountpoints must exist, since root is read-only initially
    # might be worth checking for this stuff at kexec-time
  + ''
    cat > $out/bin/nextboot <<\EOF
    #!${pkgs.runtimeShell} -ex
    # This ensures that these links always exist, particularly at boot time when
    # /nix might not yet be read-write.  s6-ln is used because POSIX ln is
    # defined such that it cannot be atomic.
    ${pkgs.s6-portable-utils}/bin/s6-ln -sfn /run/current-system /nix/var/nix/gcroots/current-system
    ${pkgs.s6-portable-utils}/bin/s6-ln -sfn /run/booted-system  /nix/var/nix/gcroots/booted-system
    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/nextboot --set ${builtins.placeholder "out"}
  '' + lib.optionalString (delete-generations != null) ''
    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/nextboot --delete-generations ${lib.escapeShellArg delete-generations} || true
    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/activated --delete-generations ${lib.escapeShellArg delete-generations} || true
  '' +
  # The fallbackboot profile is a "safe fallback" boot option.
  #
  # The fallbackboot profile provides the following guarantee: if fallbackboot exists,
  # it points to a profile that (a) booted and (b) worked well enough to
  # successfully run the bin/nextboot of some (possibly other) profile.
  #
  # After updating the nextboot profile, we set the fallbackboot profile to
  # /run/booted-system.  Note that we don't use /run/current-system here,
  # because the only thing we know /run/current-system is that it *activated*
  # successfully -- but its kernel or initrd might have fatal flaws.  This
  # means that in order to fully garbage collect the profile that booted your
  # system, you must run bin/nextboot on some other profile, reboot to that
  # profile (which updates the /run/booted-system gcroot), run bin/nextboot a
  # second time, and then `nix profile wipe-history` both nextboot and
  # fallbackboot.
  ''
    if [ -e $(${pkgs.busybox}/bin/realpath /run/booted-system) ]; then
      ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/fallbackboot --set /run/booted-system
  '' + lib.optionalString (delete-generations != null) ''
      ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/fallbackboot --delete-generations ${lib.escapeShellArg delete-generations} || true
  '' + ''
    fi
  '' + lib.optionalString (boot.loader.update or null != null) ''
    if [ -e /nix/var/nix/profiles/fallbackboot ]; then
      ${boot.loader.update} /nix/var/nix/profiles/nextboot /nix/var/nix/profiles/fallbackboot
    else
      ${boot.loader.update} /nix/var/nix/profiles/nextboot /nix/var/nix/profiles/nextboot
    fi
  '' + lib.optionalString (delete-generations != null) ''
      echo
      ${pkgs.nix}/bin/nix-store --gc
  '' + ''
      echo
      ${pkgs.nix}/bin/nix-store --gc --print-roots | ${pkgs.busybox}/bin/grep -v ^/proc
      echo
  ''
  # busybox df does not search for the enclosing mountpoint, so we use coreutils
  + ''
      ${pkgs.coreutils}/bin/df -h /nix/store
      echo
    EOF

    chmod +x $out/bin/*
    cp ${pkgs.doas}/bin/doas $out/bin/doas.unwrapped

    ${mkBootDir}
    ln -s ${sw} $out/sw
   '' +
   # sanity-check that bin/{sh,env} exist: without them things will fail quite badly.
   ''
     test -e $out/sw/bin/sh || (echo profiles must have a sw/bin/sh; exit -1)
     test -e $out/sw/bin/env || (echo profiles must have a sw/bin/env; exit -1)
   ''
  )).overrideAttrs (previousAttrs: {
      meta = (previousAttrs.meta or {}) // { mainProgram = "activate"; };
      passthru = (previousAttrs.passthru or {}) // {
        inherit source boot;
        vm = lib.makeOverridable (
          {
            storeDir, memSize-mbytes
          }:
            let
              args = [
                "-m" (toString memSize-mbytes)
                "-nographic"
                "-no-reboot" # shutdown means exit
                "-virtfs" "local,path=${storeDir},security_model=none,readonly=on,mount_tag=nixstore,id=nixstore_dev"
                "-device" "virtio-9p-pci,fsdev=nixstore_dev,mount_tag=nixstore"
                "-net" "none"
                "-vga" "none"
                "-kernel" (toString configuration.boot.kernel.payload)
                "-initrd" (toString configuration.boot.initrd.image)
              ];
            in
              pkgs.writeShellScriptBin "vm-${configuration.name}.sh" ''
                exec ${(pkgs.callPackage "${pkgs.path}/nixos/lib/qemu-common.nix" {}).qemuBinary pkgs.qemu} \
                  ${lib.escapeShellArgs args} \
                  -append "$(cat ${configuration}/boot/kernel-params)"
              ''
        )

        {
          storeDir = builtins.storeDir;
          memSize-mbytes  = 512;
        };
      };
    });
in
host-prev // {
  inherit configuration;
}
