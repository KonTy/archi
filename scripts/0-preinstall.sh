#!/usr/bin/env bash
#github-action genshdoc
#
# @file Preinstall
# @brief Contains the steps necessary to configure and pacstrap the install to selected drive. 


source $CONFIGS_DIR/setup.conf
iso=$(curl -4 ifconfig.co/country-iso)
timedatectl set-ntp true
pacman -S --noconfirm linux
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
sgdisk --zap-all ${DISK}

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

echo "Prepare UEFI boot partition"
mkfs.fat -F32 ${DISK}

echo "Prepare LUKS volume"
cryptsetup luksFormat ${DISK}p2
cryptsetup open ${DISK}p2 cryptlvm

echo "Make a LVM and filesystems and a system volume group"
pvcreate /dev/mapper/cryptlvm
vgcreate ${VOLUME_GROUP_NAME} /dev/mapper/cryptlvm
lvcreate -L ${RAM_SIZE} -n swap ${VOLUME_GROUP_NAME}
lvcreate -L 50G -n root ${VOLUME_GROUP_NAME}
lvcreate -L 8G -n tmp ${VOLUME_GROUP_NAME}
lvcreate -L 30G -n var ${VOLUME_GROUP_NAME}
lvcreate -l 100%FREE -n home ${VOLUME_GROUP_NAME}

echo "Mounting everthing"
mount /dev/${VOLUME_GROUP_NAME}/root /mnt
mount /dev/${VOLUME_GROUP_NAME}/var /mnt/var
mount /dev/${VOLUME_GROUP_NAME}/tmp /mnt/tmp
mount /dev/${VOLUME_GROUP_NAME}/home /mnt/home
mount --bind /etc /mnt/etc

# mountinh EFI psrtition sd s boot psrtition
mount ${DISK}p1 /mnt/boot

echo "use 'lsblk -f' to list information about all partition and devices"
lsblk -f
ls /mnt/boot

# /etc: Use --bind to mount the existing /etc from the host system to the chroot environment.
# Other directories (/var, /tmp, /home, /boot): Directly mount the logical volumes to the corresponding directories in the chroot environment.

genfstab -L -p /mnt >> /mnt/etc/fstab
echo " 
  Generated /etc/fstab:
"
cat /mnt/etc/fstab


echo -ne "
-------------------------------------------------------------------------
                    Arch Install on Main Drive
-------------------------------------------------------------------------
"
pacstrap /mnt base base-devel linux linux-firmware nano sudo archlinux-keyring wget libnewt --noconfirm --needed
# not sure why Chris used ubuntu keyserver for Arch?
# echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
echo "keyserver hkps://hkps.pool.sks-keyservers.net" >> /mnt/etc/pacman.d/gnupg/gpg.conf

cp -R ${SCRIPT_DIR} /mnt/root/${SCRIPTHOME_DIR}
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "System is in EFI mode"
    grub-install --boot-directory=/mnt/boot ${DISK}
    arch-chroot /mnt
    grub-mkconfig -o /boot/grub/grub.cfg
#    efibootmgr -c -d ${DISK} -p 1 -L "Arch Linux" -l /EFI/grub/grubx64.efi
else
    pacstrap /mnt efibootmgr --noconfirm --needed
fi

# echo "Press any key to continue..."
# read -n 1 -s key

echo -ne "
-------------------------------------------------------------------------
                    Checking for low memory systems <8G
-------------------------------------------------------------------------
"
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -lt 8000000 ]]; then
    # Put swap into the actual system, not into RAM disk, otherwise there is no point in it, it'll cache RAM into RAM. So, /mnt/ everything.
    mkdir -p /mnt/opt/swap # make a dir that we can apply NOCOW to to make it btrfs-friendly.
    chattr +C /mnt/opt/swap # apply NOCOW, btrfs needs that.
    dd if=/dev/zero of=/mnt/opt/swap/swapfile bs=1M count=2048 status=progress
    chmod 600 /mnt/opt/swap/swapfile # set permissions.
    chown root /mnt/opt/swap/swapfile
    mkswap /mnt/opt/swap/swapfile
    swapon /mnt/opt/swap/swapfile
    # The line below is written to /mnt/ but doesn't contain /mnt/, since it's just / for the system itself.
    echo "/opt/swap/swapfile	none	swap	sw	0	0" >> /mnt/etc/fstab # Add swap to fstab, so it KEEPS working after installation.
fi
echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 1-setup.sh
-------------------------------------------------------------------------
"
