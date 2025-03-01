#!/bin/bash

if [ -z "$1" ]; then
    echo "Provide the disk(s) to be formatted as CLI argument(s)."
    echo "WARNING !!!! THIS WILL ERASE ALL DATA ON THOSE HARD DRIVES!!"
    exit 1
fi

clear

echo "                        WARNING!!! WARNING!!!"
echo " "
DRIVE_COUNT=0
for DRIVE in "${@:1}"; do
    if [ ! -b $DRIVE ]; then
        echo "$DRIVE doesn't exist!! Aborting..."
        exit 2
    fi

    echo $DRIVE exists AND WILL BE ERASED!!
    DRIVE_COUNT=$(($DRIVE_COUNT + 1));
done
echo "Drive count: $DRIVE_COUNT"
echo ""

SINGLE_DRIVE=("${1}2" "${1}3" "${1}4" "${1}5") 
MULTI_DRIVES=("/dev/md0" "/dev/md1" "/dev/md2" "/dev/md3")
PARTITIONS=("/dev/sda2" "/dev/sda3" "/dev/sda4" "/dev/sda5")

if [ $DRIVE_COUNT -gt 1 ]; then
    PARTITIONS=("${MULTI_DRIVES[@]}")
else
    PARTITIONS=("${SINGLE_DRIVE[@]}")
fi

for str in ${PARTITIONS[@]}; do
  echo "           $str"
done
echo ""

read -p "This will install Arch Linux, automagically. But it will ERASE ALL DATA ON HARD DRIVES LISTED ABOVE. Continue? (y/N) " yesOrNo
if [ $yesOrNo != 'y' ]; then
    echo "Bailing out!!"
    exit
fi

cp arch-chroot.sh /tmp/arch-chroot

function partitionDrives() {
    echo "${@:1}"
    for DRIVE in "${@:1}"; do 
        sfdisk $DRIVE < partition-table.sfdisk
    done

    if [ $DRIVE_COUNT -gt 1 ]; then
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
    fi
}

partitionDrives "$@"

# Format /boot
for DRIVE in "${@:1}"; do 
    echo mkfs.fat "${DRIVE}1"
    mkfs.fat "${DRIVE}1"
done

# Format /
echo mkfs.btrfs -f ${PARTITIONS[0]}
mkfs.btrfs -f ${PARTITIONS[0]}

mkswap ${PARTITIONS[1]}

# Format /var/lib/docker
echo mkfs.btrfs -f ${PARTITIONS[2]}
mkfs.btrfs -f ${PARTITIONS[2]}

# # Format /code /important /var/www
# echo mkfs.btrfs -f ${PARTITIONS[3]}
# mkfs.btrfs -f ${PARTITIONS[3]}

# Format /storage
echo mkfs.xfs -f ${PARTITIONS[3]}
mkfs.xfs -f ${PARTITIONS[3]}

mkdir -p /media/arch

mount -o compress=lzo ${PARTITIONS[0]} /media/arch
cd /media/arch
btrfs subvolume create @boot
btrfs subvolume create @rootfs
btrfs subvolume create @snapshots
btrfs subvolume create @code
btrfs subvolume create @important

cd -
umount /media/arch;
mount -o compress=lzo,subvol=@rootfs ${PARTITIONS[0]} /media/arch

ORIG_PWD=$PWD

cd /media/arch
mkdir code
mount ${PARTITIONS[0]} code
pushd code
btrfs subvolume create @code
btrfs subvolume create @snapshots
ls
cd -
umount /media/arch/code
mount -o subvol=@code ${PARTITIONS[0]} /media/arch/code
pushd /media/arch/code
ls

mkdir -p /media/arch/boot
mount -o subvol=@boot ${PARTITIONS[0]} /media/arch/boot
mkdir -p /media/arch/boot/efi
mount /dev/sda1 /media/arch/boot/efi

## Resume
# mount -o compress=lzo,subvol=@rootfs ${PARTITIONS[0]} /media/arch
# mount -o subvol=@code ${PARTITIONS[2]} /media/arch/code
# mount /dev/sda1 /media/arch/boot/efi


pushd /media/arch/code
git clone https://github.com/wick3dr0se/archstrap; pushd "${_##*/}"
time TMPDIR=/media/arch ./archstrap /media/arch

pushd /media/arch
rm -r archrootfs/boot/
mv archrootfs/* .
rm -r archrootfs/

mkdir -p /media/arch/var/lib/docker
mount ${PARTITIONS[2]} /media/arch/var/lib/docker

mkdir /media/arch/storage
mount ${PARTITIONS[3]} /media/arch/storage

# Set default subvolume to @rootfs.
btrfs subvolume set-default $(btrfs subvolume list /media/arch | grep @rootfs | awk '{print $2}') /media/arch

mkdir -p /media/arch/media/true-root
mount -o subvol=/ ${PARTITIONS[0]} /media/arch/media/true-root/

cp -avf $ORIG_PWD /media/arch/code

#echo "You must now run this command:"
/tmp/arch-chroot /media/arch /code/AutoArchLinux/chroot-installer.sh
