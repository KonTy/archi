#!/bin/bash

# Script version
VERSION="v1.0.1"

# Exit on error
set -e

# Print ASCII logo and version
print_logo() {
    echo "   _____                .__    .__  .___                 __         .__  .__                "
    echo "  /  _  \_______   ____ |  |__ |__| |   | ____   _______/  |______  |  | |  |   ___________ "
    echo " /  /_\  \_  __ \_/ ___\|  |  \|  | |   |/    \ /  ___/\   __\__  \ |  | |  | _/ __ \_  __ \\"
    echo "/    |    \  | \/\  \___|   Y  \  | |   |   |  \\___ \  |  |  / __ \|  |_|  |_\  ___/|  | \/"
    echo "\____|__  /__|    \___  >___|  /__| |___|___|  /____  > |__| (____  /____/____/\___  >__|   "
    echo "        \/            \/     \/              \/     \/            \/               \/        "
    echo "Arch Installer Script $VERSION"
}

# Ensure the script is run as root
ensure_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

# Check for internet connection
check_internet() {
    if ! ping -c 1 archlinux.org &> /dev/null; then
        echo "No internet connection. Please connect to the internet before running this script."
        exit 1
    fi
}

# Prompt user with timeout
prompt_with_timeout() {
    local question=$1
    local default_option=$2
    local timeout=$3
    local -n options=$4
    
    echo "$question"
    echo "Options: ${options[@]}"
    echo -n "Default option: $default_option. Press enter to use default or choose another: "
    
    if read -t $timeout choice && [[ " ${options[@]} " =~ " $choice " ]]; then
        echo "$choice"
    else
        echo "$default_option"
    fi
}

# Detect the largest SSD/NVMe
detect_disk() {
    lsblk -o NAME,SIZE,TYPE,MODEL | grep -E "disk|nvme" | sort -k2 -h
}

# Detect if running on a Surface Laptop
detect_surface() {
    if dmesg | grep -i "surface" &> /dev/null; then
        echo "Surface device detected"
        return 0
    else
        return 1
    fi
}

# Install Surface Laptop specific modules
install_surface_modules() {
    echo "Checking for Surface Laptop..."
    if detect_surface; then
        echo "Adding the linux-surface repository..."
        echo "[linux-surface]
Server = https://pkg.surfacelinux.com/arch/" >> /mnt/etc/pacman.conf

        echo "Updating package database..."
        arch-chroot /mnt pacman -Sy

        echo "Installing Surface Laptop modules..."
        arch-chroot /mnt pacman -S --noconfirm linux-surface linux-surface-headers iptsd
        arch-chroot /mnt systemctl enable iptsd

        # Edit mkinitcpio.conf to include necessary modules
        echo "Adding Surface-specific modules to initramfs..."
        arch-chroot /mnt sed -i 's/^MODULES=()/MODULES=(8250_dw surface_hid_core surface_hid surface_aggregator_registry surface_aggregator_hub surface_aggregator)/' /etc/mkinitcpio.conf

        # Add model-specific modules
        if lscpu | grep -q "AMD"; then
            arch-chroot /mnt sed -i 's/^MODULES=(/& pinctrl_amd/' /etc/mkinitcpio.conf
        else
            arch-chroot /mnt sed -i 's/^MODULES=(/& intel_lpss intel_lpss_pci/' /etc/mkinitcpio.conf
            if lscpu | grep -q "Ice Lake"; then
                arch-chroot /mnt sed -i 's/^MODULES=(/& pinctrl_icelake/' /etc/mkinitcpio.conf
            elif lscpu | grep -q "Tiger Lake"; then
                arch-chroot /mnt sed -i 's/^MODULES=(/& pinctrl_tigerlake/' /etc/mkinitcpio.conf
            fi
        fi

        # For Surface Laptop 3/Surface Book 3 and later
        if [[ $(detect_surface) == *"Surface Laptop 3"* ]] || [[ $(detect_surface) == *"Surface Book 3"* ]] || [[ $(detect_surface) == *"Surface Laptop 4"* ]] || [[ $(detect_surface) == *"Surface Laptop Studio"* ]]; then
            arch-chroot /mnt sed -i 's/^MODULES=(/& surface_hid/' /etc/mkinitcpio.conf
        fi

        # Re-generate initramfs
        arch-chroot /mnt mkinitcpio -P
    else
        echo "Surface Laptop not detected, skipping Surface-specific modules."
    fi
}

# Prompt for user choices
prompt_user_choices() {
    local display_server_options=("wayland" "xorg")
    local init_system_options=("runit" "systemd" "openrc")
    local secure_boot_options=("yes" "no")

    display_server=$(prompt_with_timeout "Choose display server (wayland or xorg)" "wayland" 15 display_server_options)
    init_system=$(prompt_with_timeout "Choose init system (runit, systemd, openrc)" "runit" 15 init_system_options)
    secure_boot=$(prompt_with_timeout "Do you want to set up Secure Boot? (yes or no)" "no" 15 secure_boot_options)

    echo "Please enter the password to be used for root:"
    read -s ROOT_PASSWORD

    echo "Please enter the password to be used for disk encryption:"
    read -s DISK_PASSWORD
}

# Confirm the detected disk
confirm_disk() {
    echo "Detecting the largest SSD/NVMe..."
    DISK=$(detect_disk | tail -n 1 | awk '{print $1}')
    DISK="/dev/$DISK"

    echo "The largest detected disk is: $DISK"
    read -p "Is this correct? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Exiting. Please run the script again and manually specify the disk."
        exit 1
    fi
}

# Unmount all partitions and deactivate swap on the disk
unmount_and_deactivate_swap() {
    echo "Unmounting all partitions and deactivating swap on $DISK..."

    # Unmount all partitions
    for partition in $(lsblk -ln -o NAME,MOUNTPOINT | grep "^${DISK}" | awk '{print $1}'); do
        if mount | grep -q "/dev/$partition"; then
            umount -f "/dev/$partition"
        fi
    done

    # Deactivate swap
    for swap in $(swapon --show=NAME --noheadings | grep "^${DISK}"); do
        swapoff "$swap"
    done
}

# Partition and format the disk
partition_and_format_disk() {
    echo "Wiping the disk..."
    wipefs -a $DISK

    echo "Partitioning the disk..."
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

    mkfs.fat -F32 ${DISK}p1

    echo -n $DISK_PASSWORD | cryptsetup luksFormat --type luks2 ${DISK}p2 --batch-mode --key-file=-
    echo -n $DISK_PASSWORD | cryptsetup open ${DISK}p2 cryptroot --key-file=-

    mkfs.ext4 /dev/mapper/cryptroot

    mount /dev/mapper/cryptroot /mnt
    mkdir /mnt/boot
    mount ${DISK}p1 /mnt/boot
}

# Install base and additional packages
install_base_and_packages() {
    echo "Installing base and additional packages..."

    pacstrap /mnt base linux linux-firmware networkmanager grub efibootmgr dialog nano vi lvm2

    if [ "$display_server" = "wayland" ]; then
        pacstrap /mnt hyprland waybar kitty wofi rofi swaync ranger thunar neovim plasma-meta
    else
        pacstrap /mnt plasma-meta xorg-server xorg-apps xorg-xinit
    fi

    if [ "$init_system" = "runit" ]; then
        pacstrap /mnt runit
    elif [ "$init_system" = "openrc" ]; then
        pacstrap /mnt openrc
    fi
}

# Configure the system
configure_system() {
    echo "Configuring the system..."
    genfstab -U /mnt >> /mnt/etc/fstab

    arch-chroot /mnt <<EOF

    ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
    hwclock --systohc

    bootctl install

    cat <<EOL > /boot/loader/entries/arch.conf
    title Arch Linux
    linux /vmlinuz-linux
    initrd /intel-ucode.img
    initrd /initramfs-linux.img
    options cryptdevice=UUID=$(blkid -s UUID -o value ${DISK}p2):cryptroot root=/dev/mapper/cryptroot rw
    EOL

    cat <<EOL > /boot/loader/loader.conf
    default arch
    timeout 5
    EOL

    echo "root:$ROOT_PASSWORD" | chpasswd

    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab

    systemctl enable NetworkManager
    systemctl enable libvirtd

    usermod -aG kvm,qemu,libvirt $(whoami)

    echo "options vfio-pci ids=vendor:device" > /etc/modprobe.d/vfio.conf
    echo "vfio" >> /etc/modules-load.d/vfio.conf
    echo "vfio_iommu_type1" >> /etc/modules-load.d/vfio.conf
    echo "vfio_pci" >> /etc/modules-load.d/vfio.conf
    echo "vfio_virqfd" >> /etc/modules-load.d/vfio.conf

EOF
}

# Secure Boot setup
setup_secure_boot() {
    if [ "$secure_boot" = "yes" ]; then
        echo "Setting up Secure Boot..."
        pacstrap /mnt sbctl
        arch-chroot /mnt sbctl create-keys
        arch-chroot /mnt sbctl enroll-keys
        arch-chroot /mnt sbctl sign -s /boot/vmlinuz-linux
        arch-chroot /mnt sbctl sign -s /boot/initramfs-linux.img
        arch-chroot /mnt sbctl sign -s /boot/initramfs-linux-fallback.img
    fi
}

# Finalize and reboot
finalize_and_reboot() {
    echo "Finalizing installation and rebooting..."
    umount -R /mnt
    cryptsetup close cryptroot
    echo "Installation complete. Rebooting..."
    reboot
}

# Main function
main() {
    print_logo
    ensure_root
    check_internet
    prompt_user_choices
    confirm_disk
    unmount_and_deactivate_swap
    partition_and_format_disk
    install_base_and_packages
    configure_system
    install_surface_modules
    setup_secure_boot
    finalize_and_reboot
}

# Run the main function
main
