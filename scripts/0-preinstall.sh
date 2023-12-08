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
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc dm_mod dm_crypt
modprobe dm_mod
modprobe dm_crypt

echo -ne "
-------------------------------------------------------------------------
                    Formating Disk
-------------------------------------------------------------------------
"
# make sure everything is unmounted before we start
umount -A --recursive /mnt 2>/dev/null 
# disk prep
echo "Zapping disk: ${DISK}"
wipefs -af ${DISK}
sgdisk --zap-all ${DISK}

# lsblk
# echo "Press any key to continue..."
# read -n 1 -s key

echo -ne "
-------------------------------------------------------------------------
                    Creating Paritions 
-------------------------------------------------------------------------
"

#!/bin/bash

# Disk Information
DISK="/dev/nvme0n1"
VOLUME_GROUP_NAME="archvg"

# Unattended Installation
timedatectl set-ntp true

# Partitioning
sgdisk -a 2048 -o $DISK

# Create EFI System Partition (512M)
sgdisk -n 1:1M:+600M -t 1:ef00 -c 1:"EFI System" $DISK

# Create ROOT Partition (Remaining space)
sgdisk -n 2::-0 -t 2:8300 -c 2:"ROOT" $DISK

# Encrypt ROOT Partition
cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 cryptlvm

# Create LVM
pvcreate /dev/mapper/cryptlvm
vgcreate $VOLUME_GROUP_NAME /dev/mapper/cryptlvm

# Create ROOT Logical Volume
lvcreate -l 100%FREE $VOLUME_GROUP_NAME -n root

# Format ROOT Partition
mkfs.btrfs -L ROOT /dev/mapper/$VOLUME_GROUP_NAME-root

# Mount ROOT Partition
mount /dev/mapper/$VOLUME_GROUP_NAME-root /mnt

# Mount EFI System Partition
mkdir -p /mnt/boot/efi
mkfs.fat -F 32 /dev/nvme0n1p1
mount /dev/nvme0n1p1 /mnt/boot
#mount /dev/nvme0n1p1 /mnt/boot/efi

# Chroot into the new system
arch-chroot /mnt /bin/bash -c '
  ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime;
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
  echo "en_US ISO-8859-1" >> /etc/locale.gen
  locale-gen
  pacman -S --noconfirm grub efibootmgr;
  efibootmgr --create --disk /dev/nvme0n1 --part 1 --loader /EFI/GRUB/grubx64.efi --label "GRUB";
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub --boot-directory=/boot/efi --debug;
  grub-install --recheck --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub;
  grub-mkconfig -o /boot/grub/grub.cfg;
  genfstab -p -U / >> /etc/fstab;
'





  # echo ----- LS BOOT EFI;
  # ls /boot/EFI/BOOT/BOOTx64.EFI;
  # SOURCE_PATH="/boot/EFI/BOOT/BOOTx64.EFI"
  # DEST_PATH="/boot/EFI/Microsoft/Boot/bootmgfw.efi";
  # mkdir -p "$(dirname $DEST_PATH)";
  # cp "$SOURCE_PATH" "$DEST_PATH";
  # echo "Arch Linux boot loader copied to Microsoft Boot directory.";
  # # Bootstrap Arch Linux
  # pacstrap / base linux linux-firmware;
  # # Generate fstab












# # efibootmgr -b XXXX -B  # Replace XXXX with the boot entry number
# efibootmgr --create --disk /dev/nvme0n1 --part 1 --loader /EFI/GRUB/grubx64.efi --label "GRUB"
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
# grub-mkconfig -o /boot/grub/grub.cfg
# pacman -S refind-efi
# refind-install



# # Create Swap File
# RAM_SIZE_GB=$(free --giga | awk '/^Mem:/ {print $2}')
# fallocate -l "${RAM_SIZE_GB}G" /mnt/swapfile
# chmod 600 /mnt/swapfile
# mkswap /mnt/swapfile
# swapon /mnt/swapfile




# # VOLUME_GROUP_NAME="systemvg"

# # sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# # # First partition (512M)
# # sgdisk -n 1::512M -t 1:ef00 -c 1:"EFI System" ${DISK}

# # # Second partition (rest of the disk) 8309 is used for LUKS 
# # # but it is not a hard standard you can fall back to 8300 as a generic Linux partition
# # sgdisk -n 2::-0 -t 2:8300 -c 2:"Linux" ${DISK}

# # # lsblk
# # # echo "Press any key to continue..."
# # # read -n 1 -s key

# # echo "Prepare UEFI boot partition"
# # mkfs.vfat -F32 -n "EFIBOOT" ${DISK}p1


# # cryptsetup luksClose ${VOLUME_GROUP_NAME}-root
# # umount ${DISK}p2
# # wipefs --all ${DISK}p2
# # mount | grep ${DISK}p2
# # mkfs.btrfs -L ROOT ${DISK}p2

# # #mkfs.fat -F32 ${DISK}p1

# # echo "Prepare LUKS volume"

# # LUKS_PASSWORD="hooy"
# # echo -n "${LUKS_PASSWORD}" | cryptsetup -y -v luksFormat ${DISK}p2 -
# # # open luks container and ROOT will be place holder 
# # echo -n "${LUKS_PASSWORD}" | cryptsetup open ${DISK}p2 ROOT -
# # mount -t btrfs ${DISK}p2 /mnt


# # btrfs subvolume create /mnt/@
# # btrfs subvolume create /mnt/@home
# # btrfs subvolume create /mnt/@var
# # btrfs subvolume create /mnt/@tmp
# # btrfs subvolume create /mnt/@.snapshots

# # umount /mnt

# # MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120"
# # # mount @ subvolume
# # mount -o ${MOUNT_OPTIONS},subvol=@ ${DISK}p2 /mnt
# # # make directories home, .snapshots, var, tmp
# # mkdir -p /mnt/{home,var,tmp,.snapshots}
# # mount -o ${MOUNT_OPTIONS},subvol=@home ${partition3} /mnt/home
# # mount -o ${MOUNT_OPTIONS},subvol=@tmp ${partition3} /mnt/tmp
# # mount -o ${MOUNT_OPTIONS},subvol=@var ${partition3} /mnt/var
# # mount -o ${MOUNT_OPTIONS},subvol=@.snapshots ${partition3} /mnt/.snapshots

# # echo ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value ${partition3}) >> $CONFIGS_DIR/setup.conf

# # # mount target
# # mkdir -p /mnt/boot/efi
# # mount -t vfat -L EFIBOOT /mnt/boot/

# # if ! grep -qs '/mnt' /proc/mounts; then
# #     echo "Drive is not mounted can not continue"
# #     echo "Rebooting in 3 Seconds ..." && sleep 1
# #     echo "Rebooting in 2 Seconds ..." && sleep 1
# #     echo "Rebooting in 1 Second ..." && sleep 1
# #     echo "Press any key to continue..."
# #     read -n 1 -s key

# # #    reboot now
# # fi


# # echo "Make a LVM and filesystems and a system volume group"
# # pvcreate /dev/mapper/ROOT
# # vgcreate ${VOLUME_GROUP_NAME} /dev/mapper/ROOT
# # # lvcreate -L ${RAM_SIZE} -n swap ${VOLUME_GROUP_NAME}
# # lvcreate -L 50G -n root ${VOLUME_GROUP_NAME}
# # lvcreate -L 8G -n tmp ${VOLUME_GROUP_NAME}
# # lvcreate -L 30G -n var ${VOLUME_GROUP_NAME}
# # lvcreate -l 100%FREE -n home ${VOLUME_GROUP_NAME}

# # lvdisplay /dev/${VOLUME_GROUP_NAME}/*
# # echo "Press any key to continue..."
# # read -n 1 -s key

# # # cryptsetup luksDump /dev/*
# # # echo "Press any key to continue..."
# # # read -n 1 -s key

# # # echo "Mounting everthing"
# # # cryptsetup luksOpen /dev/mapper/${VOLUME_GROUP_NAME}-root root
# # # cryptsetup luksOpen /dev/mapper/${VOLUME_GROUP_NAME}-var var
# # # cryptsetup luksOpen /dev/mapper/${VOLUME_GROUP_NAME}-tmp tmp
# # # cryptsetup luksOpen /dev/mapper/${VOLUME_GROUP_NAME}-home home

# # # mount /dev/mapper/root /mnt
# # # mount /dev/mapper/var /mnt/var
# # # mount /dev/mapper/tmp /mnt/tmp
# # # mount /dev/mapper/home /mnt/home

# # mount /dev/${VOLUME_GROUP_NAME}/root /mnt
# # mount /dev/${VOLUME_GROUP_NAME}/var /mnt/var
# # mount /dev/${VOLUME_GROUP_NAME}/tmp /mnt/tmp
# # mount /dev/${VOLUME_GROUP_NAME}/home /mnt/home


# # mkdir /mnt/etc
# # mount --bind /etc /mnt/etc

# # # mountinh EFI psrtition sd s boot psrtition
# # mount ${DISK}p1 /mnt/boot

# echo "use 'lsblk -f' to list information about all partition and devices"
# lsblk
# ls /mnt/boot
# ls /mnt

# echo "Press any key to continue..."
# read -n 1 -s key


# # /etc: Use --bind to mount the existing /etc from the host system to the chroot environment.
# # Other directories (/var, /tmp, /home, /boot): Directly mount the logical volumes to the corresponding directories in the chroot environment.

# arch-chroot /mnt /bin/bash <<EOF
#     genfstab -L -p /mnt >> /mnt/etc/fstab
# EOF
# echo " 
#   Generated/mnt/etc/fstab:
# "
# ls /mnt/etc
# cat /mnt/etc/fstab

# echo "Press any key to continue for fstab..."
# read -n 1 -s key

echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"

# # arch-chroot /mnt
# # grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
# # grub-mkconfig -o /boot/grub/grub.cfg


# if [[ ! -d "/sys/firmware/efi" ]]; then
#     echo "System is in EFI mode"

#     arch-chroot /mnt /bin/bash <<EOF
#         grub-install --boot-directory=/mnt/boot ${DISK}
#         grub-mkconfig -o /boot/grub/grub.cfg
# EOF

# #    efibootmgr -c -d ${DISK} -p 1 -L "Arch Linux" -l /EFI/grub/grubx64.efi

# else
#     pacstrap /mnt efibootmgr --noconfirm --needed
# fi

# echo "Press any key to continue..."
# read -n 1 -s key

# echo -ne "
# -------------------------------------------------------------------------
#                     Checking for low memory systems <8G
# -------------------------------------------------------------------------
# "


# # Variables
# SWAP_SIZE="$TOTAL_RAM"  # Size of the swap file in megabytes
# SWAP_DIR="/opt/swap"  # Directory to store the swap file

# arch-chroot /mnt /bin/bash <<EOF
#   chattr +C ${SWAP_DIR}  # apply NOCOW, btrfs needs that.
#   dd if=/dev/zero of=${SWAP_DIR}/swapfile bs=1M count=${SWAP_SIZE} status=progress
#   chmod 600 ${SWAP_DIR}/swapfile  # set permissions.
#   chown root ${SWAP_DIR}/swapfile
#   mkswap ${SWAP_DIR}/swapfile
#   swapon ${SWAP_DIR}/swapfile
# EOF


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


# # Exit chroot and unmount partitions
# umount -R /mnt
# cryptsetup close cryptlvm
# reboot









echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 1-setup.sh
-------------------------------------------------------------------------
"
