#!/bin/bash
clear
echo "Hello! Welcome to the Auto Arch Linux Installer!"
echo ""
echo For help and support see https://github.com/bitbasket/AutoArchLinux/
echo ""

echo "Set password for root: "
passwd

read -p "Username for local admin? " user
useradd -m $user -G adm,wheel,users

echo "Set password for $user: "
passwd $user

# Enable the en_US locales
sed -i s/#en_US/en_US/ /etc/locale.gen
locale-gen


pacman -Syu
pacman -S --noconfirm git vim sudo docker xfsprogs btrfs-progs mdadm linux-lts \
                      openssh grub efibootmgr dmidecode gdisk dosfstools net-tools \
                      ack nano gptfdisk
systemctl enable sshd
usermod -a -G docker $user

clear
echo "Generate SSH key for root:"
ssh-keygen -t ed25519

clear
echo "Generate SSH for the local admin ($user)..."
echo ====================================================================================
echo === Make sure you set a password, as this key will also be used for sudo auth... ===
echo ====================================================================================

sudo -u $user ssh-keygen -t ed25519

genfstab -U / > /etc/fstab

mkdir -p /boot/grub
grub-mkconfig > /boot/grub/grub.cfg

# Install grub:
if efibootmgr > /dev/null; then 
    echo "Installing Grub for UEFI..."; 
else
    echo "Setting up the 1 MiB BIOS boot partition..."
    echo "Step 1: Backup the parititon table..."
    sgdisk --backup=partition-table-backup.gpt /dev/nvme0n1
    echo "Step 2: Delete and recreate partition 1..."
    umount /dev/nvme0n1p1
    sgdisk --delete=1 /dev/nvme0n1
    sgdisk --new=1:2048:+8192s --typecode=1:EF00 --change-name=1:"EFI system partition" /dev/nvme0n1
    echo "Step 3: Create BIOS Boot Partition..."
    sgdisk --new=6:10240:+2048s --typecode=6:21686148-6449-6E6F-744E-656564454649 --change-name=6:"BIOS boot partition" /dev/nvme0n1

    echo "Step 4: Recreate the file system on partition 1..."
    mkfs.fat -F32 /dev/nvme0n1p1

    echo "Step 5: Regenerate /etc/fstab..."
    genfstab -U / > /etc/fstab 

    echo "Step 6: Install Grub for BIOS...";
    grub-install --target=i386-pc /dev/nvme0n1
fi

echo "Enabling btrfs and mdadm in Grub boots..."
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^BINARIES=()/BINARIES=(\/usr\/bin\/btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(base udev/HOOKS=(base udev mdadm_udev/' /etc/mkinitcpio.conf
mkinitcpio -P

MAC_ADDRESS=$(cat /sys/class/net/eth0/address)
IPV4_ADDRESS=$(ip -4 addr show enp0s31f6  | grep inet | awk '{print $2}')
IPV4_GATEWAY=$(ip -4 route show default | awk '{print $3}')
IPV6_ADDRESS=$(ip -6 addr show | awk '/inet6/ {print $2}' | grep -v fe80 | grep -v ::1/128)
IPV6_GATEWAY=$(ip -6 route show default | awk '{print $3}')

cat > /etc/systemd/network/10-wired.network <<CONFIG
[Match]
Match=${MAC_ADDRESS}

[Network]
Address=${IPV4_ADDRESS}
Gateway=${IPV4_GATEWAY}
DNS=1.1.1.1
DNS=8.8.8.8

[Network]
Address=${IPV6_ADDRESS}
Gateway=${IPV6_GATEWAY}
CONFIG

echo "Here is your network config. Check for correctness."
cat /etc/systemd/network/10-wired.network

# Set the server's hostname.
read -p "What is the server's hostname? " $hostname
echo $hostname > /etc/hostname

# Fix Archstrap's hostname in Bash:
sed -i 's/\(PS1=.\+\)archstrap\(.\+\)/\1\\h\2/'  /etc/bash.bashrc

systemctl enable systemd-networkd

# Fix Archstrap's PS1:
cat >> /etc/bash.bashrc <<BASH

if [ $(id -u) -eq 0 ]; then 
    export PS1='\[\033[01;31m\]\h \[\033[01;34m\]\W # \[\033[00m\]'; 
else
    export PS1='\[\]15:20.54\[\]\[\033[38;5;12m\][\[\]\[\033[38;5;10m\]xperion77\[\]\[\033[38;5;12m\]@\[\]\[\033[38;5;7m\]\h\[\]\[\033[38;5;12m\]]\[\]\[\033[38;5;15m\]: \[\]\[\033[38;5;7m\]\w\[\]\[\033[38;5;12m\]>\[\]\[\033[38;5;10m\]\$\[\]\[\033[38;5;15m\] \[\]'
fi
BASH

echo "Adding $user to /etc/sudoers"
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "Installing yay (AUR)..."
pacman -S --noconfirm base-devel
cd /code
setfacl -Rm d:g:users:rwX /code
setfacl -Rm g:users:rwX /code
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u ${user} makepkg -si

ln -s /usr/share/zoneinfo/UTC /etc/localtime

clear
cat <<LETTER
Your system should now be fully installed!

We have done the following:
 - Rationally partitioned the drives into
    - EFI / BIOS
    - / [btrfs, daily snapshots]; 100 GB RAID-0
    - /code, /var/www, /important [btrfs, hourly snapshots], 100 GB RAID-1
    - /var/lib/docker [btrfs], 10 GB RAID-0
    - /storage [xfs], remaing space, RAID-1
 - Installed Arch Linux
 - Installed Git, Docker, Vim, nano, base-devel, OpenSSH and legacy network tools.
 - Installed the Linux-LTS kernel.
 - Automatically setup the network via systemd's networkd in /etc/systemd/network/.
 - Installed sudo and setup a sudo user.
 - Set up an OpenSSH server.
 - Configured the time zone to UTC (/etc/localtime).
 - Configured the system to use CloudFlare DNS (1.1.1.1) and Google DNS (8.8.8.8).
 - Installed the AUR package manager yay.

For help and support see https://github.com/bitbasket/AutoArchLinux/

Now, reboot your system and pray that it all works fine.
LETTER
