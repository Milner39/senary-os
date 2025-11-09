{ lib
, writeScript
, runtimeShell
, chpst
, writeExecline
, ...
}:

let

  # There are many places (`run`, `up`, `down`, `finish`) where s6 calls for an
  # arbitrary user-provided script to run.  Six lets you specify these scripts
  # in a few different ways:
  #
  # - as a path: will be `execv()`ed
  # - as a derivation: outpath will be `execv()`ed
  # - as a list: will be passed to `writeExecline`
  # - as an attrset: will be passed to `six.util.chpst`
  #
  scriptify = { name }: script:
    if   lib.isString script || lib.isDerivation script || lib.isPath script
    then script
    else writeExecline name
      { argMode = "none"; }
      (if !(lib.isAttrs script)
       then script
       else chpst ({
         envdir = "./env";
         redirect-stderr-to-stdout = true;
         # TODO: consider these
         #dir ? null,
         #new-session ? false,
         #new-process-group ? new-session,
         #user ? null,
         #group ? null,
         #groups ? [],
         #env-clear ? false,
       } // script));
in
scriptify
