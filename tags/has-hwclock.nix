{ lib
, yants
, infuse
, ...
}:

host-final: host-prev: infuse host-prev ({
  service-overlays.__append = [(final: prev:
    assert !(host-final.tags.has-hwclock-fake or false);
    infuse prev {
      targets.hwclock = _: final.services.hwclock { };
    })];
})
