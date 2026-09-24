# SenaryOS

[![Nix Flake](https://img.shields.io/badge/nix-flake-5277c3?logo=nixos&logoColor=white)](https://nixos.org)

> [!NOTE]
> This repo (**senary-os**) is a fork of **[sixos](https://codeberg.org/amjoseph/sixos)**, 
> the Nix-based operating system without systemd, created by Adam Joseph. 
> This fork is not affiliated with or endorsed by the sixos project. Please 
> report problems with senary-os [here](https://github.com/milner39/senary-os/issues), 
> not upstream.

SenaryOS is a Linux distribution derived from sixos.


## Relationship to upstream

- **Upstream:** <https://codeberg.org/amjoseph/sixos> (branch `master`) 
- **Forked:** 24 September 2026, from upstream commit `58bdc55` 
- **Changes:** everything this fork adds is in the git history, 
  `git log upstream/master..main` lists it
- **Licence:** like sixos, SenaryOS is licensed under the GNU GPL, version 3 
  only. See [COPYING.GPL3-ONLY](COPYING.GPL3-ONLY).


## Inspiration

None of this could have been done without Adam Joseph's work on 
**[sixos](https://codeberg.org/amjoseph/sixos)**, 
**[infuse](https://codeberg.org/amjoseph/infuse.nix)**, 
the original **[six-demo](https://codeberg.org/amjoseph/six-demo)**, 
and more.

I recommend everyone watches Adam's 
**[talk on sixos](https://media.ccc.de/v/38c3-sixos-a-nix-os-without-systemd)**.

I really loved his take on an improved service declaration system, and also the 
general idea of a non-systemd nixos. I've made this fork to hopefully take the 
idea further without stepping on Adam's toes and to have the freedom to develop 
at my own pace and with my own ideas of what could be done.

Thanks Adam :)
