{
  lib,
  infuse,
}:
[
  (final: prev: infuse prev ({

    skawarePackages.s6-rc.__output.patches.__append = [
      ./patches/s6-rc/0001-doc-s6-rc-compile.html-document-bundle-flattening.patch
      ./patches/s6-rc/0002-doc-define-singleton-bundle-document-special-rules.patch
      ./patches/s6-rc/0003-libs6rc-s6rc_graph_closure.c-add-comments-explaining.patch
      ./patches/s6-rc/0004-s6-rc-update.c-add-define-constants-for-bitflags.patch
      ./patches/s6-rc/0005-s6-rc-update.c-rewrite-O-n-2-loop-as-O-n-complexity.patch
      ./patches/s6-rc/0006-WIP-s6-rc-update.c-add-additional-comments.patch
      #./patches/s6-rc/0007-Revert-Simplify-selfpipe-management.patch
      ./patches/s6-rc/0008-s6-rc-update.c-bugfix-for-failure-to-create-pipe-s6r.patch
      ./patches/s6-rc/0009-add-OLDSTATE_UNPROPAGATED_RESTART.patch
      ./patches/s6-rc/0010-disable-restart-if-acquired-new-dependency-behavior.patch
    ];

    busybox.__output.patches.__append = [
      ./patches/busybox/modprobe-dirname-flag.patch
    ];

    abduco.__output.patches.__append =  [
      ./patches/abduco/dont-use-alternate-buffer.patch
    ];
  }))
]

