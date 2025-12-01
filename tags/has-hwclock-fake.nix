{ lib
, yants
, infuse
, ...
}:

host-final: host-prev: infuse host-prev
  (assert !(host-final.tags.has-hwclock or false); {
    targets.hwclock-fake.__assign         = host-final.services.hwclock-fake { };
    targets.hwclock-fake-updater.__assign = host-final.services.hwclock-fake-updater { };
  })
