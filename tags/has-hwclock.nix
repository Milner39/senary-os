{ lib
, yants
, infuse
, ...
}:

host-final: host-prev: infuse host-prev
  (assert !(host-final.tags.has-hwclock-fake or false); {
    targets.hwclock = _: host-final.services.hwclock { };
  })
