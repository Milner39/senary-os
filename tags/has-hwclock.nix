{ lib
, yants
, infuse
, ...
}:

host-final: host-prev: infuse host-prev
  ({
    targets.hwclock = _: host-final.services.hwclock { };
  })
