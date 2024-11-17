#!/bin/bash

clear

echo "                        WARNING!!! WARNING!!!"
echo " "
read -p "This will install Arch Linux, automagically. But it will ERASE ALL DATA ON HARD DRIVES. Continue? (y/N) " yesOrNo
if [ $yesOrNo != 'y' ]; then
    echo "Bailing out!!"
    exit
fi

cp arch-chroot.sh /usr/bin/arch-chroot

sfdisk /dev/nvme0n1 < partition-table.sfdisk
sfdisk /dev/nvme1n1 < partition-table.sfdisk

# Destroy existing RAID arrays.
#mdadm --zero-superblock /dev/nvme0n1p2 /dev/nvme1n1p2 /dev/nvme0n1p3 /dev/nvme1n1p3 /dev/nvme0n1p4 /dev/nvme1n1p4 /dev/nvme0n1p5 /dev/nvme1n1p5

# /
mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 /dev/nvme0n1p2 /dev/nvme1n1p2
# /var/lib/docker
mdadm --create --verbose /dev/md1 --level=0 --raid-devices=2 /dev/nvme0n1p3 /dev/nvme1n1p3
# /code /var/www /important
mdadm --create --verbose /dev/md2 --level=1 --raid-devices=2 /dev/nvme0n1p4 /dev/nvme1n1p4
# /storage
mdadm --create --verbose /dev/md3 --level=1 --raid-devices=2 /dev/nvme0n1p5 /dev/nvme1n1p5

# Format /boot
mkfs.fat /dev/nvme0n1p1
mkfs.fat /dev/nvme1n1p1

# Format /
mkfs.btrfs /dev/md0

# Format /var/lib/docker
mkfs.btrfs /dev/md1

# Format /code /important /var/www
mkfs.btrfs /dev/md2

# Format /storage
mkfs.xfs /dev/md3


mount -o compress=lzo /dev/md0 /media
cd /media
btrfs subvolume create @boot
btrfs subvolume create @rootfs
btrfs subvolume create @snapshots

cd -
umount /media
mount -o compress=lzo,subvol=@rootfs /dev/md0 /media

ORIG_PWD=$PWD

cd /media
mkdir code
mount /dev/md2 code
cd code
btrfs subvolume create @code
btrfs subvolume create @snapshots
ls
cd -
umount /media/code
mount -o subvol=@code /dev/md2 /media/code
cd /media/code
ls

mkdir -p /media/boot
mount -o subvol=@boot /dev/md0 /media/boot
mkdir -p /media/boot/efi
mount /dev/nvme0n1p1 /media/boot/efi

## Resume
mount -o compress=lzo,subvol=@rootfs /dev/md0 /media
mount -o subvol=@code /dev/md2 /media/code
mount /dev/nvme0n1p1 /media/boot/efi


cd /media/code
git clone https://github.com/wick3dr0se/archstrap; cd "${_##*/}"
time ./archstrap /media

cd /media
rm -r archrootfs/boot/
mv archrootfs/* .
rm -r archrootfs/

mkdir /media/var/lib/docker
mount /dev/md1 /media/var/lib/docker

mkdir /media/storage
mount /dev/md3 /media/storage

# Set default subvolume to @rootfs.
btrfs subvolume set-default $(btrfs subvolume list /media | grep @rootfs | awk '{print $2}') /media

mkdir -p /media/media/true-root
mount -o subvol=/ /dev/md0 /media/media/true-root/

cp -avf $ORIG_PWD/AutoArchLinux /media/code
chroot /media /code/AutoArchLinux/chroot-installer.sh
