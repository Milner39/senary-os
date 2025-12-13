{ lib,
  types,
  infuse,
  sixos,
  ...
}:

let


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
}
