#!/usr/bin/env bash
#github-action genshdoc
#
# @file Preinstall
# @brief Contains the steps necessary to configure and pacstrap the install to selected drive. 

echo "Error" >&2

source $CONFIGS_DIR/setup.conf
iso=$(curl -4 ifconfig.co/country-iso)
timedatectl set-ntp true
# pacman -S --noconfirm linux
pacman -S --noconfirm archlinux-keyring #update keyrings to latest to prevent packages failing to install
pacman -S --noconfirm --needed pacman-contrib terminus-font
setfont ter-v28b
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -S --noconfirm --needed reflector rsync grub
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
echo -ne "
-------------------------------------------------------------------------
                    Setting up $iso mirrors for faster downloads
-------------------------------------------------------------------------
"
#reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
#mkdir /mnt &>/dev/null # Hiding error message if any
echo -ne "
-------------------------------------------------------------------------
                    Installing Prerequisites
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc






echo -ne "
-------------------------------------------------------------------------
                    Formating Disk
-------------------------------------------------------------------------
"
# make sure everything is unmounted before we start
umount -A --recursive /mnt 2>/dev/null 
# disk prep
echo "Zapping disk: ${DISK}"
cryptsetup luksOpen --clear ${DISK} temporary_name
sgdisk --zap-all ${DISK}

lsblk
echo "Press any key to continue..."
read -n 1 -s key

echo -ne "
-------------------------------------------------------------------------
                    Creating Paritions 
-------------------------------------------------------------------------
"

VOLUME_GROUP_NAME="systemvg"

sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# First partition (512M)
sgdisk -n 1::512M -t 1:ef00 -c 1:"EFI System" ${DISK}

# Second partition (rest of the disk) 8309 is used for LUKS 
# but it is not a hard standard you can fall back to 8300 as a generic Linux partition
sgdisk -n 2:: -t 2:8309 -c 2:"Linux LUKS" ${DISK}

lsblk
echo "Press any key to continue..."
read -n 1 -s key


echo "Prepare UEFI boot partition"
mkfs.fat -F32 ${DISK}p1

echo "Prepare LUKS volume"
echo "your_passphrase" | cryptsetup luksFormat --force-password ${DISK}p2
cryptsetup open ${DISK}p2 cryptlvm

echo "Make a LVM and filesystems and a system volume group"
pvcreate /dev/mapper/cryptlvm
vgcreate ${VOLUME_GROUP_NAME} /dev/mapper/cryptlvm
# lvcreate -L ${RAM_SIZE} -n swap ${VOLUME_GROUP_NAME}
lvcreate -L 50G -n root ${VOLUME_GROUP_NAME}
lvcreate -L 8G -n tmp ${VOLUME_GROUP_NAME}
lvcreate -L 30G -n var ${VOLUME_GROUP_NAME}
lvcreate -l 100%FREE -n home ${VOLUME_GROUP_NAME}

echo "Mounting everthing"
cryptsetup luksOpen /dev/${VOLUME_GROUP_NAME}/root root
cryptsetup luksOpen /dev/${VOLUME_GROUP_NAME}/var var
cryptsetup luksOpen /dev/${VOLUME_GROUP_NAME}/tmp tmp
cryptsetup luksOpen /dev/${VOLUME_GROUP_NAME}/home home

mount /dev/mapper/root /mnt
mount /dev/mapper/var /mnt/var
mount /dev/mapper/tmp /mnt/tmp
mount /dev/mapper/home /mnt/root/home

mount --bind /etc /mnt/root/etc

# mountinh EFI psrtition sd s boot psrtition
mount ${DISK}p1 /mnt/boot

echo "use 'lsblk -f' to list information about all partition and devices"
lsblk -f
ls /mnt/boot
ls /mnt

echo "Press any key to continue..."
read -n 1 -s key


# /etc: Use --bind to mount the existing /etc from the host system to the chroot environment.
# Other directories (/var, /tmp, /home, /boot): Directly mount the logical volumes to the corresponding directories in the chroot environment.

arch-chroot /mnt /bin/bash <<EOF
    genfstab -L -p /mnt >> /mnt/etc/fstab
EOF
echo " 
  Generated/mnt/etc/fstab:
"
ls /mnt/etc
cat /mnt/etc/fstab

echo "Press any key to continue for fstab..."
read -n 1 -s key

echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"

# arch-chroot /mnt
# grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
# grub-mkconfig -o /boot/grub/grub.cfg


if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "System is in EFI mode"

    arch-chroot /mnt /bin/bash <<EOF
        grub-install --boot-directory=/mnt/boot ${DISK}
        arch-chroot /mnt
        grub-mkconfig -o /boot/grub/grub.cfg
EOF

#    efibootmgr -c -d ${DISK} -p 1 -L "Arch Linux" -l /EFI/grub/grubx64.efi

else
    pacstrap /mnt efibootmgr --noconfirm --needed
fi

echo "Press any key to continue..."
read -n 1 -s key

echo -ne "
-------------------------------------------------------------------------
                    Checking for low memory systems <8G
-------------------------------------------------------------------------
"


# Variables
SWAP_SIZE="$TOTAL_RAM"  # Size of the swap file in megabytes
SWAP_DIR="/opt/swap"  # Directory to store the swap file

arch-chroot /mnt /bin/bash <<EOF
  chattr +C ${SWAP_DIR}  # apply NOCOW, btrfs needs that.
  dd if=/dev/zero of=${SWAP_DIR}/swapfile bs=1M count=${SWAP_SIZE} status=progress
  chmod 600 ${SWAP_DIR}/swapfile  # set permissions.
  chown root ${SWAP_DIR}/swapfile
  mkswap ${SWAP_DIR}/swapfile
  swapon ${SWAP_DIR}/swapfile
EOF


echo -ne "
-------------------------------------------------------------------------
                    Arch Install on Main Drive
-------------------------------------------------------------------------
"
arch-chroot /mnt /bin/bash <<EOF
    pacstrap /mnt base base-devel linux linux-firmware nano sudo archlinux-keyring wget libnewt --noconfirm --needed
    # not sure why Chris used ubuntu keyserver for Arch?
    # echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
    echo "keyserver hkps://hkps.pool.sks-keyservers.net" >> /mnt/etc/pacman.d/gnupg/gpg.conf

    cp -R ${SCRIPT_DIR} /mnt/${SCRIPTHOME_DIR}
    cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
EOF










echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 1-setup.sh
-------------------------------------------------------------------------
"
