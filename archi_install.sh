#!/bin/bash

# Function to print ASCII logo and version
print_logo_and_version() {
    VERSION="v1.0.2"
    echo "
   _____                .__    .__  .___                 __         .__  .__                
  /  _  \_______   ____ |  |__ |__| |   | ____   _______/  |______  |  | |  |   ___________ 
 /  /_\  \_  __ \_/ ___\|  |  \|  | |   |/    \ /  ___/\   __\__  \ |  | |  | _/ __ \_  __ \
/    |    \  | \/\  \___|   Y  \  | |   |   |  \\___ \  |  |  / __ \|  |_|  |_\  ___/|  | \/
\____|__  /__|    \___  >___|  /__| |___|___|  /____  > |__| (____  /____/____/\___  >__|   
        \/            \/     \/              \/     \/            \/               \/       
    "
    echo "Version: $VERSION"
}

# Function to print steps
print_step() {
    echo "----> $1"
}

# Function to prompt user with timeout
prompt_with_timeout() {
    local question=$1
    local default_option=$2
    local timeout=$3
    local options=("wayland" "xorg")
    
    echo "$question"
    echo "Options: ${options[@]}"
    echo -n "Default option: $default_option. Press enter to use default or choose another: "
    
    if read -t $timeout choice && [[ " ${options[@]} " =~ " $choice " ]]; then
        echo "$choice"
    else
        echo "$default_option"
    fi
}

# Function to prompt user to choose init system
choose_init_system() {
    local options=("runit" "systemd" "openrc")
    local timeout=15
    
    echo "Choose init system (runit, systemd, openrc)"
    echo "Options: ${options[@]}"
    
    if read -t $timeout choice && [[ " ${options[@]} " =~ " $choice " ]]; then
        echo "$choice"
    else
        echo "runit"  # Default choice if no input within timeout
    fi
}

# Function to detect the largest SSD/NVMe
detect_disk() {
    lsblk -o NAME,SIZE,TYPE,MODEL | grep -E "disk|nvme" | sort -k2 -h
}

# Function to setup Surface modules
setup_surface_modules() {
    print_step "Setting up Surface modules"
    echo -e "8250_dw\nsurface_hid_core\nsurface_hid\nsurface_aggregator_registry\nsurface_aggregator_hub\nsurface_aggregator" >> /etc/mkinitcpio.conf
    # Rebuild initramfs
    mkinitcpio -P
}

# Exit on error
set -e

# Print ASCII logo and version
print_logo_and_version

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check for internet connection
print_step "Checking for internet connection"
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "No internet connection. Please connect to the internet before running this script."
    exit 1
fi

# Detect if Wayland or Xorg should be installed
display_server=$(prompt_with_timeout "Choose display server (wayland or xorg)" "wayland" 15)

# Detect if init system should be installed
init_system=$(choose_init_system)

# Update the system clock
print_step "Updating the system clock"
timedatectl set-ntp true

# Detect the largest disk
print_step "Detecting the largest SSD/NVMe"
DISK=$(detect_disk | tail -n 1 | awk '{print $1}')
DISK="/dev/$DISK"

# Confirm the detected disk
echo "The largest detected disk is: $DISK"
read -p "Is this correct? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Exiting. Please run the script again and manually specify the disk."
    exit 1
fi

# Prompt for the root password
echo "Please enter the password to be used for root:"
read -s ROOT_PASSWORD

# Prompt for the disk encryption password
echo "Please enter the password to be used for disk encryption:"
read -s DISK_PASSWORD

# Wipe the disk
print_step "Wiping the disk"
wipefs -a $DISK

# Partition the disk
print_step "Partitioning the disk"
(
echo g # Create a new GPT partition table
echo n # Add a new partition
echo   # Default partition number
echo   # Default first sector
echo +512M # 512MB for EFI system partition
echo t # Change partition type
echo 1 # EFI system
echo n # Add a new partition
echo   # Default partition number
echo   # Default first sector
echo   # Default last sector (remaining space)
echo t # Change partition type
echo 2 # Select partition 2
echo 30 # Set partition type to LUKS
echo w # Write changes
) | fdisk $DISK

# Format the EFI partition
print_step "Formatting the EFI partition"
mkfs.fat -F32 ${DISK}p1

# Setup LUKS on the main partition
print_step "Setting up LUKS on the main partition"
echo -n $DISK_PASSWORD | cryptsetup luksFormat --type luks2 ${DISK}p2 --batch-mode --key-file=-
echo -n $DISK_PASSWORD | cryptsetup open ${DISK}p2 cryptroot --key-file=-

# Format the LUKS container with Btrfs
print_step "Formatting the LUKS container with Btrfs"
mkfs.btrfs /dev/mapper/cryptroot

# Mount the Btrfs filesystem
print_step "Mounting the Btrfs filesystem"
mount /dev/mapper/cryptroot /mnt

# Create Btrfs subvolumes
print_step "Creating Btrfs subvolumes"
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@snapshots
btrfs su cr /mnt/@var_log

# Mount the subvolumes
print_step "Mounting the subvolumes"
umount /mnt
mount -o noatime,compress=zstd,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,.snapshots,var/log}
mount -o noatime,compress=zstd,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o noatime,compress=zstd,space_cache=v2,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log

# Mount the EFI partition
print_step "Mounting the EFI partition"
mount ${DISK}p1 /mnt/boot

# Install base packages
print_step "Installing base packages"
pacstrap /mnt base linux linux-firmware btrfs-progs cryptsetup

# Install display server and desktop environment based on user choice
print_step "Installing display server and desktop environment"
if [ "$display_server" = "wayland" ]; then
    pacstrap /mnt hyprland waybar kitty wofi rofi swaync ranger thunar neovim plasma-meta
else
    pacstrap /mnt plasma-meta xorg-server
fi

# Install init system
print_step "Installing init system"
if [ "$init_system" = "runit" ]; then
    pacstrap /mnt runit
elif [ "$init_system" = "openrc" ]; then
    pacstrap /mnt openrc
fi

# Configure mkinitcpio
print_step "Configuring mkinitcpio"
arch-chroot /mnt mkinitcpio -p linux

# Generate an fstab file
print_step "Generating an fstab file"
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system
print_step "Changing root into the new system"
arch-chroot /mnt <<EOF

# Set the time zone
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

# Install and configure bootloader (systemd-boot in this case)
bootctl install

# Configure bootloader entries
cat <<EOL > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options cryptdevice=UUID=$(blkid -s UUID -o value ${DISK}p2):cryptroot root=/dev/mapper/cryptroot rw
EOL

# Set root password
echo root:$ROOT_PASSWORD | chpasswd

# Setup Surface modules
$(setup_surface_modules)

EOF

# Unmount all partitions
print_step "Unmounting all partitions"
umount -R /mnt

# Reboot into the new system
print_step "Rebooting into the new system"
reboot
