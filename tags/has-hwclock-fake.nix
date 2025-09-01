{ lib
, yants
, infuse
, ...
}:

host-final: host-prev: infuse host-prev ({
  service-overlays.__append = [(final: prev:
    assert !(host-final.tags.has-hwclock or false);
    infuse prev {
      targets.hwclock-fake.__assign         = final.services.hwclock-fake { };
      targets.hwclock-fake-updater.__assign = final.services.hwclock-fake-updater { };
    })];
})
