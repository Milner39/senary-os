{ lib
, pkgs
, six
}:
six.mkFunnel {
  # TO DO: drop privs with `-u`, `-g`, '-U`, `-G`
  run.argv = [
    "${pkgs.s6}/bin/s6-socklog" "-t" "60" "-x" "/dev/log"
  ];
}
