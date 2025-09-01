{ lib
, yants
, infuse
, ...
}:

host: prev: infuse prev ({
    service-overlays.__append = [(final: prev: infuse prev {
      targets = old-targets: old-targets //
                             (lib.flip lib.mapAttrs host.boot.initrd.ttys
                               (tty-device: tty-baud:
                                 final.six.mkFunnel {
                                   run = final.pkgs.writeScript "console" ''
                                     #!${final.pkgs.runtimeShell}
                                     echo 'to kill the vm, type: `reboot -f`'
                                     export PATH="/run/current-system/sw/bin:/run/init/bin:${final.pkgs.busybox}/bin:$PATH"
                                     cd /root
                                     exec ${final.pkgs.busybox}/bin/getty -nl ${final.pkgs.busybox}/bin/sh ${toString (if tty-baud==null then 38400 else tty-baud)} ${tty-device}
                                   '';
                                 })
                             );
    })];
  })
