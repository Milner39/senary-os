{ lib
, six
, pkgs
, listen-port ? 22
, package ? pkgs.openssh
, user ? "_sshd"
, group ? "_sshd"
}:
let
  package' = package.overrideAttrs (previousAttrs: {
    configureFlags = (previousAttrs.configureFlags or []) ++ [
      # unfortunately this can be set only at compile time; there is no way to
      # override it from sshd_config.  the "default default" is
      # /bin:/usr/bin:... which is unusable
      "--with-default-path=/run/current-system/sw/bin"

      # another compile-time-only configurable :(
      "--with-privsep-user=${user}"
    ];
  });
in let package = package'; in
let
  configFile = builtins.toFile "sshd_config" ''
Port ${toString listen-port}
#ListenAddress 0.0.0.0
# see https://bugzilla.mindrot.org/show_bug.cgi?id=1357#c1
AddressFamily inet

# I can't figure out how to get `ssh-keygen -A` to put the end result anywhere
# other than directly in /etc, ugh
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
#SyslogFacility AUTH
#LogLevel INFO
PermitRootLogin yes
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
UsePAM no
#AllowAgentForwarding yes
#AllowTcpForwarding yes
#GatewayPorts no
X11Forwarding yes
#PermitTTY yes
PrintMotd no
#PrintLastLog yes
#TCPKeepAlive yes
#Compression delayed
#ClientAliveInterval 0
#ClientAliveCountMax 3
UseDNS no
#PidFile /var/run/sshd.pid
#MaxStartups 10:30:100
#PermitTunnel no
#ChrootDirectory none
#VersionAddendum none
Banner none

# read ~/.ssh/environment, which we need in order to guarantee that nix-store is
# in root's $PATH for `nix copy`
PermitUserEnvironment yes

# Allow client to pass locale environment variables
AcceptEnv LANG LC_*
Subsystem sftp internal-sftp
  '';

  maybe-generate-host-keys = pkgs.writeScript "maybe-generate-ssh-host-keys"
''
#!${pkgs.runtimeShell}
# generate host keys if not present
# ugly kludge due to `ssh-keygen -f` taking a prefix rather than a destination
mkdir -p /etc/ssh
TEMP="$(mktemp -d)"
(cd "$TEMP"
 ln -s /etc/ssh etc
 ssh-keygen -A -f ./
 rm etc)
rmdir "$TEMP"
'';

in
six.mkFunnel {

  env = {
    # nixpkgs has a patch to pass this variable through from sshd to children
    LOCALE_ARCHIVE = "/run/current-system/sw/lib/locale/locale-archive";
  };

  mkdir = {
    "/var/empty" = "0755";  # configuration activation should take care of this...
    "/run/sshd" = "0755";
  };

  run.pre-argvs = [
    [ "${maybe-generate-host-keys}" ]
  ];

  run.argv = [
    "${package}/bin/sshd"
    "-e"   # log to stderr
    "-4"   # disable ipv6
    "-D"   # don't detach (double-fork)
    "-f" configFile
  ];

  passthru.user = user;
  passthru.group = group;
}
