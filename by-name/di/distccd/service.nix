{ lib
, pkgs
, six
, targets
, package ? pkgs.distcc
, user ? "_distccd"
, group ? "_distccd"
, extraArgs ? []
, port ? 3632
, allowed-client-networks ? [ "127.0.0.1" ]
, job-timeout ? null
, log-level ? "warning"
, max-jobs ? null
, nice ? null
}:

six.mkFunnel {

  inherit user group;

  run.env = {
    PATH = "${pkgs.distccMasquerade}/bin";
  };

  run.argv = [
    "${package}/bin/distccd"
    "--no-detach"
    "--daemon"
    "--enable-tcp-insecure"
    "--port" "${toString port}"
  ] ++ lib.optionals (job-timeout != null) [
    "--job-lifetime" (toString job-timeout)
  ] ++ lib.optionals (log-level != null) [
    "--log-level" log-level
  ] ++ lib.optionals (nice != null) [
    "--nice" (toString nice)
  ] ++ lib.optionals (max-jobs != null) [
    "--jobs" (toString max-jobs)
  ] ++ (
    lib.concatMapStrings (c: [ "--allow" c ]) allowed-client-networks
  ) ++ extraArgs;

  passthru.after = [ targets.global.coldplug ];
}
