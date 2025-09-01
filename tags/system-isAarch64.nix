{ lib
, yants
, infuse
, ...
}:

final: prev: infuse prev ({

  # aarch64 machines generally don't have battery-backed hardware clocks
  tags.has-hwclock-fake.__default = true;

})
