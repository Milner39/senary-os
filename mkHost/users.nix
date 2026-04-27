{ lib,
  types,
  infuse,
  sixos,
  ...
}:

let


  # Creates users and groups which must exist on every sixos system
  create-sixos-users-and-groups = host-final: host-prev:
    infuse host-prev ({
      users.root.uid.__init = 0;
      users.root.home-directory.__default = "/root";
      users.root.shell.__default = "${host-final.pkgs.busybox}/bin/ash";
      groups.root.gid.__init = 0;

      users.nobody.uid.__init = globally-allocated.nobody;
      users.nobody.gid.__init = globally-allocated.nogroup;
      groups.nogroup.gid.__init = globally-allocated.nogroup;

      # FIXME this should be triggered by services.mdevd being enabled
      groups._video.gid.__init = globally-allocated._video;
      groups._audio.gid.__init = globally-allocated._audio;
      groups._input.gid.__init = globally-allocated._input;

      # nix 2.3 fails with incredibly cryptic error messages when there is no
      # build-users-group or when it has no users.  To avoid this footgun, for
      # now, we simply create that user and group on every sixos install.
      # FIXME: instead, create these only if services.nix-daemon is enabled.
      users._nixbld1.uid.__init = globally-allocated._nixbld1;
      users._nixbld1.gid.__init = globally-allocated._nixbld;
      groups._nixbld.gid.__init = globally-allocated._nixbld;

      # used by doas, which is a required component of sixos
      groups.wheel.gid.__init = globally-allocated.wheel;
    });

  # Sixos follows a few of the UID/GID policies of Debian/Ubuntu.  This overlay
  # checks that the site overlay has not violated them.
  #
  # 0:0         must be root:root
  # 99:99       must be wheel:wheel (for `doas`)
  # 1000-59999  is (currently) the only range available for site-specific use
  # 60000-64999 may only be allocated by sixos (see below)
  # 65534:65534 must be nobody:nogroup
  # 65535:65535 may never be used (16-bit error sentinel).
  #
  # UID/GID ranges not listed above are reserved for future use.  32-bit userids
  # are not currently supported, but may be in the future.
  #
  # The UID and GID ranges 60000-64999 are allocated by sixos for
  # package-specific users/groups.  Most of these are daemon-specific userids --
  # for example, the sshd privilege-separation UID/GID.  All usernames and
  # groupnames in this range will start with an underscore `_`.
  #
  # https://www.debian.org/doc/debian-policy/ch-opersys.html#uid-and-gid-classes
  #
  enforce-uid-gid-policies = host-final: host-prev:
    let
      enforce-uid-policies-on-site-user = user-name: user:
        assert user?uid && !(user.uid >= 1000)  -> throw "userids less than 1000 are reserved; user ${user-name} has uid ${user.uid}";
        assert user?uid && !(user.uid <= 59999) -> throw "userids greater than 59999 are reserved; user ${user-name} has uid ${user.uid}";
        user;
      enforce-gid-policies-on-site-group = group-name: group:
        assert group?gid && !(group.gid >= 1000)  -> throw "groupids less than 1000 are reserved; group ${group-name} has gid ${group.gid}";
        assert group?gid && !(group.gid <= 59999) -> throw "userids greater than 59999 are reserved; group ${group-name} has gid ${group.gid}";
        group;
      enforce-uid-policies-on-user = user-name: user:
        assert !(user-name == "root"    <-> (user.uid==0))     -> throw "userid 0 must be root";
        assert !(user-name == "nobody"  <-> (user.uid==65534)) -> throw "userid 65534 must be nobody";
        assert user.uid==65535 -> throw "the userid 65535 may not be used; it is the 16-bit error sentinel";
        assert !(user.uid >= 60000 && user.uid <= 64999 && !(lib.strings.hasPrefix "_" user-name))
                -> throw "users with a UID in the range 60000-64999 must have a username starting with `_`";
        true;
      enforce-gid-policies-on-group = group-name: group:
        assert !(group-name == "root"    <-> (group.gid==0))     -> throw "groupid 0 must be root";
        assert !(group-name == "nogroup" <-> (group.gid==65534)) -> throw "groupid 65534 must be nogroup";
        assert group.gid==65535 -> throw "the groupid 65535 may not be used; it is the 16-bit error sentinel";
        assert !(group.gid >= 60000 && group.gid <= 64999 && !(lib.strings.hasPrefix "_" group-name))
                -> throw "groups with a GID in the range 60000-64999 must have a group name starting with `_`";
        true;
    in
      assert
        (lib.all lib.id (
          # Applied to host-prev to check what the site-specific overlay has done.
          # The enforce-uid-gid-policies overlay must be applied after the
          # site-specific overlay but before the global sixos users (like `root`)
          # are added.
          lib.mapAttrsToList enforce-uid-policies-on-site-user host-prev.users ++
          lib.mapAttrsToList enforce-gid-policies-on-site-group host-prev.groups ++

          # Applied to host-final to check the result of both the site-specific
          # overlay and the sixos global users.
          lib.mapAttrsToList enforce-uid-policies-on-user host-final.users ++
          lib.mapAttrsToList enforce-gid-policies-on-group host-final.groups ++
        []
        ));
      host-prev;

  #
  # Globally allocated userids for all sixos systems; for each integer both the
  # UID and GID are allocated simultaneously with the same name.
  #
  # If your service needs a uid/gid, please ask for an entry to be added to this
  # table.  Except in unusual circumstances the {user,group}-name should be the
  # service name (i.e. directory name beneath by-name) prefixed with an
  # underscore.
  #
  # Please reference reserved uids/gids by looking them up in this table rather
  # than by hardcoding the integer into your service.  This makes it easier to
  # emit warnings in case .
  #
  # TODO: to avoid merge conflicts and ease maintenance, move these into
  # by-name/*/*/userid.nix, containing just an integer.
  #
  globally-allocated = {
    root = 0;
    wheel = 99;       # GID only

    _sshd            = 60001;
    _lprng           = 60002;
    _ntpd            = 60003;
    _i2pd            = 60004;
    _tor             = 60005;
    _bitcoind        = 60006;
    _monerod         = 60007;
    _geth            = 60008;
    _gpsd            = 60009;
    _electrs         = 60010;
    _tftpd           = 60011;
    _chrony          = 60012;
    _postgres        = 60013;
    _dnscache        = 60014;
    _dnsmasq         = 60015;
    _dnscrypt        = 60016;
    _bitmagnet       = 60017;
    _tox             = 60018;
    _mariadb         = 60019;
    _transmission    = 60020;
    _reth            = 60021;
    _redlib          = 60022;
    _distccd         = 60023;
    _actkbd          = 60024;

    # these are known to mdevd
    _input           = 60025;
    _audio           = 60026;
    _video           = 60027;

    _speakersafetyd  = 60028;

    _nixbld1         = 64999;   # UID only
    _nixbld          = 64999;   # GID only

    nobody = 65534;   # UID only
    nogroup = 65534;  # GID only
  };

  mkUser = pkgs: groups: user:
    let
      inherit (user) name;
      hashed-password = user.hashed-password or "!";
      uid = toString (user.uid or (throw "impossible"));
      gid = toString (user.gid or (if groups?name then groups.name else uid));
      comment = user.comment or "";
      home-directory = user.home-directory or "/var/empty";
      shell = user.shell or "${pkgs.util-linux}/bin/nologin";
    in
      "${name}:${hashed-password}:${uid}:${gid}:${comment}:${home-directory}:${shell}";

  mkEtcPasswd = { pkgs, users, groups }:
    lib.pipe users [

      # turn the attrset into a list of attrvalues, with the attrname stored as
      # a `name` attribute
      (lib.mapAttrsToList (name: user:
        (types.user user) // { inherit name; }))

      # sort the entries by uid while checking for duplicates
      (lib.sort (u1: u2:
        assert u1.uid == u2.uid -> throw "two users have the same uid ${toString u1.uid}";
        u1.uid < u2.uid))

      # convert the attrsets into /etc/passwd lines
      (lib.map (user: "${mkUser pkgs groups user}\n"))
      lib.concatStrings
    ];

  mkEtcGroup = { users, groups }:
    lib.pipe groups [

      # turn the attrset into a list of attrvalues, with the attrname stored as
      # a `name` attribute
      (lib.mapAttrsToList (name: group:
        assert lib.isInt group.gid;
        { inherit name; inherit (group) gid; }))

      # sort the entries by gid while checking for duplicates
      (lib.sort (g1: g2:
        assert g1.gid == g2.gid -> throw "two groups have the same gid ${toString g1.gid}";
        g1.gid < g2.gid))

      # turn each entry into a line of /etc/group
      (lib.map ({ name, gid }:
        "${name}:x:${toString gid}:${
          lib.concatStringsSep "," (groups.${name}.members or [])}\n"
      ))
      lib.concatStrings
    ];

  synthesize-groups =
    host-final: host-prev: host-prev // {
      # for each user with no `.gid` attribute, and for which there is no
      # identically-named group, synthesize a group whose gid is the user's uid
      # and whose group name is the user's user name.
      groups = host-prev.groups // lib.pipe host-prev.users [
        # filter for the users with no `.gid` attribute and no identically-named group
        (lib.filterAttrs (name: user: !(user?gid) && !(host-prev.groups?name)))

        # synthesize the group
        (lib.mapAttrsToList
          (user-name: user: lib.nameValuePair user-name {
            gid = user.uid;
            members = [ user-name ];
          }))
        lib.listToAttrs
      ];

      users = lib.mapAttrs
        (user-name: user:
          user // lib.optionalAttrs (!(user?gid)) {
            gid = user.uid;
          })
        host-prev.users;
    };

  # A user can become a member of a group in three ways:
  #
  # 1. If !(host.users.${user}?gid) then a group with the same name as the user
  #    will be synthesized and the user will become a member of it.
  # 2. Putting a group name in host.users.${user}.groups
  # 3. Putting a user name in hosts.groups.${group}.members
  #
  # The following overlay, which must run *after* any of the above modifications
  # are performed, including all site-dir overlays and synthesize-groups.
  #
  recompute-group-membership = host-final: host-prev:
    let

      # reverse-lookup; maps from integer gids to group names
      gids =
        lib.listToAttrs
          (lib.mapAttrsToList
            (name: group:
              lib.nameValuePair (toString group.gid) name)
            host-prev.groups);

      # TODO: write an "invert" function for inverting a mapping represented as
      # an attrset-of-list-of-strings, then use that primitive to unify
      # groupMembers and userMembers.

      #
      # for each ${user} in users,
      #   for each ${group} in users.${user}.groups,
      #     append ${user} to groupMembers.${group}
      #
      # The result is an attrset whose keys are group names and whose values are
      # lists of user names.
      #
      groupMembers = lib.pipe host-prev.users [
        # turn each user into a list of groups to which it belongs
        (lib.mapAttrsToList (name: user:
          # this overlay runs after synthesize-gids so user?gid==true
          [ { username = name; groupname = gids.${toString user.gid}; } ] ++
          lib.map (groupname: { username = name; inherit groupname; })
            (user.groups or [])))
        lib.concatLists

        # turn the list into an attrset with an attribute for each groupname
        (lib.groupBy (usergroup: usergroup.groupname))

        # turn the attrset-of-lists-of-attrsets into an attrset-of-lists-of-usernames
        (lib.mapAttrs (groupname: usergroup-list:
          lib.map (usergroup: usergroup.username) usergroup-list))

        # append groups.${group}.members to each list and normalize it
        (lib.mapAttrs (group-name: user-list:
          sixos.lib.sortAndDeduplicateStrings
            (host-prev.groups.${group-name}.members or []
             ++ user-list)))
      ];

      groups =
        # verify that every attrname of `groupMembers` is an attrname of `groups`;
        # this will catch spelling errors in users.${user}.groups.
        assert lib.all lib.id (lib.mapAttrsToList (groupName: _:
          if !(builtins.hasAttr groupName host-prev.groups)
          then throw "group ${groupName} appears in host.users.\${user}.groups, but does not appear in host.groups"
          else true) groupMembers);
        # Append any users who gain membership as a result of host.users.${user}.{gid,groups}
        lib.mapAttrs
          (group-name: group: group // {
            members = groupMembers.${group-name} or [];
          })
          host-prev.groups;

      # attrset whose keys are usernames and whose values are lists of group names
      userMemberships = lib.pipe groups [
        # turn each group into a list of users which belong to it
        (lib.mapAttrsToList (group-name: group:
          lib.map (user-name: { inherit user-name group-name; })
            group.members))
        lib.concatLists

        # turn the list into an attrset with an attribute for each username
        (lib.groupBy (groupuser: groupuser.user-name))

        # turn the attrset-of-lists-of-attrsets into an attrset-of-lists-of-usernames
        (lib.mapAttrs (user-name: usergroup-list:
          lib.map (usergroup: usergroup.group-name) usergroup-list))
      ];

    in host-prev // {
      inherit groups;
      users = lib.mapAttrs
        (user-name: user: user // {
          groups = let
            memberships = userMemberships.${user-name};
            primary-group = gids.${toString user.gid};
            secondary-groups = lib.filter (group-name: group-name != primary-group) memberships;
          in
            [ primary-group ] ++ sixos.lib.sortAndDeduplicateStrings secondary-groups;
        })
        host-prev.users;
    };
in


{
  inherit mkEtcPasswd;
  inherit mkEtcGroup;
  inherit synthesize-groups;
  inherit recompute-group-membership;
  inherit create-sixos-users-and-groups;
  inherit enforce-uid-gid-policies;
  inherit globally-allocated;
}
