---
title: "Fixing my GRUB install"
date: 2022-09-26T11:30:00+02:00
tags: [shell]
---

After another instance of my Laptop no longer "working" after a firmware update, I decided to write down how to recover so I know where to look for it.
<!--more-->

## How I probably broke it (again)
Keeping firmware relatively up to date is a good thing.
But `fwupd` seems to constantly break my UEFI boot, leading to my Laptop being confused and skipping the SSD, instead trying to boot vie PXE.

The first time this was terrifying but after a few repetitions, it is only annoying.
It seems the firmware updater is written into the EFI partition without any regard for the existing boot loader.
Or (more unlikely) actively breaks it during the firmware update.

But I won't pretend I have any clue about what actually happens, so let's fix the boot.

## Fixing it
Again, there might be a better way of doing it, but this worked for me.

General approach:
1. Boot a live Linux
1. Mount the filesystem(s)
1. chroot into the system
1. run grub-install

### Boot a live Linux
Somehow we need something to install GRUB, where the easiest solution is a live-cd with Linux.
In my case, I have a USB-Stick created with [Ventoy](https://www.ventoy.net/en/index.html) lying around.
This enables me to just copy an `.iso` onto it and boot from it.
I already have a relatively recent Arch Linux live-cd on it.

Insert USB stick, start computer and it is happy that there is actually something to boot.

### Mount the filesystem(s)
I remember from the Arch install, that I chrooted into the system before installing GRUB.
Technically, I need `/boot` which has the GRUB config and `/boot/efi` which contains the UEFI "stuff".

So minimal setup (I guess):
I want to mount everything up to `/boot/efi`, which in my case is 3 partitions: `/`, `/boot` and `/boot/efi`.
My setup has BTRFS on `/` (with some subvolumes), but I don't want to remember the actual commands.
Luckily I could just copy `/etc/fstab` to the live system, adopt it and then just `mount` it.

```shell
mount /dev/nvme0n1p3 /mnt # mount the root filesystem to /mnt
cp /mnt/root/etc/fstab /etc/fstab # copy out the fstab from the root subvolume
umount /mnt
vim /etc/fstab # replace / with /mnt since we already have a /
mount /mnt
mount /mnt/boot
mount /mnt/boot/efi
```

### `chroot` into the system
Simple (on the archlinux live system): `arch-chroot /mnt`

I guess this might be a bit more involved if you need to run `chroot` directly.

### Reinstall GRUB
Everything has been set up, we just need to install grub to the SSD again and then reboot (and 🤞)

```shell
grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck /dev/nvme0n1
```

## Future additions
- how to handle encrypted root/boot filesystem (yeah I know, I should have done that a long time ago)
- can I do this, only mounting `/boot/efi` and copying grub-config to the live system (aka without chroot)?
