{ lib
, yants
, infuse
, ...
}:

final: prev: assert true -> throw "this does not work, don't use it"; infuse prev ({

  # The vendor-supplied bootloader (a u-boot fork) shipped with all Octeon
  # devices communicates the initrd's memory location only via a nonstandard
  # `rd_name=` kernel parameter, which upstream kernel declines to support.
  # Below are two patches and some uboot commands which supposedly enable
  # support for this, but I couldn't get it to work.
  boot.loader.uboot.uboot-commands.__assign = [
    "usb start"
    "dhcp"
    "freeprint"
    # pick the first "Block address", round up to end with 0x0000, and use it as the second value below:
    # FIXME: shouldn't be hardcoding these
    "setenv initrd_addr 0x4e000000"
    "namedalloc my_initrd 0xb00000 $(initrd_addr)"

    # FIXME this shouldn't be hardcoded
    "tftpboot $(initrd_addr) 192.168.22.6:cedar/kernel/initrd"
    "tftpboot $(loadaddr) 192.168.22.6:cedar/kernel/vmlinux"

    "bootoctlinux $(loadaddr) numcores=$(numcores) endbootargs mem=0 rd_name=my_initrd"
  ];

  boot.kernel.package.__input.patches.__append = [
    {
      name = "octeon-rd_name.patch";
      patch = final.pkgs.fetchpatch {
        # rebase of original here: https://lore.kernel.org/all/1418666603-15159-10-git-send-email-aleksey.makarov@auriga.com/
        url = "https://raw.githubusercontent.com/alpinelinux/aports/6f0349a849b733d788fd02788c0516d689ddc6a2/main/linux-octeon/octeon-rd_name.patch";
        hash = "sha256-4W9kStw1ZHLYu/axUbkutJAgMFQzWquRChO3fFtkaTA=";
      };
    }

    {
      name = "fix-initrd-address.patch";
      patch = final.pkgs.fetchpatch {
        url = "https://lore.kernel.org/all/20230619102133.809736219@linuxfoundation.org/raw";
        hash = "sha256-53sJSN2koaGOIwrJumlRmdy22ueG3e39VUIQVG3IKYs=";
      };
    }
  ];

})
