{ lib,
  types,
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
      (lib.sort (u1: u2: assert u1.uid != u2.uid; u1.uid < u2.uid))

      # convert the attrsets into /etc/passwd lines
      (lib.map (mkUser pkgs groups))
      (lib.concatStringsSep "\n")
    ];

  mkEtcGroup = { users, groups }:
    let
      #
      # for each ${user} in users,
      #   for each ${group} in users.${user}.groups,
      #     append ${user} to groupMembers.${group}
      #
      # The result is an attrset whose keys are group names and whose values are
      # lists of user names.
      #
      groupMembers = lib.pipe users [
        # turn each user into a list of groups to which it belongs
        (lib.mapAttrsToList (name: user:
          lib.map (groupname: { username = name; inherit groupname; })
            (user.groups or [])))
        lib.concatLists

        # turn the list into an attrset with an attribute for each groupname
        (lib.groupBy (usergroup: usergroup.groupname))

        # turn the attrset-of-lists-of-attrsets into an attrset-of-lists-of-usernames
        (lib.mapAttrs (groupname: usergroup-list:
          lib.map (usergroup: usergroup.username) usergroup-list))

        # sort by username for normalization purposes
        (lib.mapAttrs (groupname: username-list:
          builtins.sort (user1: user2: user1 < user2) username-list))
      ];

    in
      # verify that every attrname of `groupMembers` is an attrname of `groups`;
      # this will catch spelling errors in users.${user}.groups.
      assert lib.all (lib.mapAttrsToList (groupName: _:
        if !(builtins.hasAttr groupName groups)
        then throw "group ${groupName} appears in host.users.\${user}.groups, but does not appear in host.groups"
        else true) groupMembers);

    lib.pipe groups [

      # turn the attrset into a list of attrvalues, with the attrname stored as
      # a `name` attribute
      (lib.mapAttrsToList (name: gid:
        assert lib.isInt gid;
        { inherit name gid; }))

      # sort the entries by gid while checking for duplicates
      (lib.sort (g1: g2: assert g1.gid != g2.gid; g1.gid < g2.gid))

      # turn each entry into a line of /etc/group
      (lib.map ({ name, gid }:
        "${name}:x:${toString gid}:${
          lib.concatStringsSep "," (groupMembers.${name} or [])}"
      ))
      (lib.concatStringsSep "\n")
    ];

in


{
  inherit mkEtcPasswd;
  inherit mkEtcGroup;
}
