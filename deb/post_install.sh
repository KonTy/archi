#!/bin/bash

# Function to detect if the current machine is a Microsoft Surface device
is_surface() {
    local model=$(cat /sys/devices/virtual/dmi/id/product_name)
    case $model in
        *Surface*) return 0 ;;  # If the model name contains "Surface", it's a Surface device
        *) return 1 ;;
    esac
}

# Function to install Surface support on Arch Linux
install_arch_surface_support() {
    # Import the signing key for Surface packages
    curl -s https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | sudo pacman-key --add -
    
    # Verify the fingerprint of the key
    sudo pacman-key --finger 56C464BAAC421453
    
    # Locally sign the imported key
    sudo pacman-key --lsign-key 56C464BAAC421453
    
    # Add the Surface repository to pacman.conf
    echo -e "\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/" | sudo tee -a /etc/pacman.conf
    
    # Refresh repository metadata
    sudo pacman -Syu
    
    # Install the linux-surface kernel and its dependencies
    sudo pacman -S linux-surface linux-surface-headers iptsd
    
    # Install additional firmware package for WiFi if needed
    local model=$(cat /sys/devices/virtual/dmi/id/product_name)
    case $model in
        *Surface*Pro*4|*Surface*Pro*5|*Surface*Pro*6|*Surface*Book*1|*Surface*Book*2|*Surface*Laptop*1|*Surface*Laptop*2)
            sudo pacman -S linux-firmware-marvell
            ;;
    esac
    
    # Install the secure boot key if secure boot is set up
    read -p "Have you set up secure boot for Arch via SHIM? (y/N): " secureboot_setup
    if [[ $secureboot_setup =~ ^[Yy]$ ]]; then
        sudo pacman -S linux-surface-secureboot-mok
        echo "Please reboot and enroll the key by following the on-screen instructions. Use the password 'surface'."
    else
        echo "Secure boot not set up. Skipping secure boot key installation."
    fi
    
    # Update GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    
    echo "Installation complete. Please reboot your system."
}

# Function to install Surface support on Debian or Ubuntu
install_debian_surface_support() {
    # Import the signing key for Surface packages
    wget -qO - https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/linux-surface.gpg
    
    # Add the Surface repository to sources.list.d
    echo "deb [arch=amd64] https://pkg.surfacelinux.com/debian release main" | sudo tee /etc/apt/sources.list.d/linux-surface.list
    
    # Update APT repository metadata
    sudo apt update
    
    # Install the linux-surface kernel and its dependencies
    sudo apt install linux-image-surface linux-headers-surface libwacom-surface iptsd
    
    # Install the secure boot key if secure boot is set up
    read -p "Have you set up secure boot for Debian or Ubuntu via SHIM? (y/N): " secureboot_setup
    if [[ $secureboot_setup =~ ^[Yy]$ ]]; then
        sudo apt install linux-surface-secureboot-mok
        echo "Please reboot and enroll the key by following the on-screen instructions. Use the password 'surface'."
    else
        echo "Secure boot not set up. Skipping secure boot key installation."
    fi
    
    # Update GRUB configuration
    sudo update-grub
    
    echo "Installation complete. Please reboot your system."
}

# Function to install yay if it is not already installed
install_yay() {
    if ! command -v yay &> /dev/null; then
        echo "yay not found, installing yay..."
        sudo pacman -S --needed git base-devel
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si
        cd ..
        rm -rf yay
    else
        echo "yay is already installed."
    fi
}


configure_arch_secure_boot() {
    # Set up directory and file paths
    SECUREBOOT_DIR=~/secureboot/keys
    MOK_KEY=${SECUREBOOT_DIR}/MOK.key
    MOK_CRT=${SECUREBOOT_DIR}/MOK.crt
    MOK_CER=${SECUREBOOT_DIR}/MOK.cer
    MOK_ESL=${SECUREBOOT_DIR}/MOK.esl
    MOK_AUTH=${SECUREBOOT_DIR}/MOK.auth
    KERNEL_PATH=/boot/vmlinuz-linux
    GRUB_PATH=/boot/efi/EFI/arch/grubx64.efi

    # Create directory for keys
    mkdir -p ${SECUREBOOT_DIR}
    cd ${SECUREBOOT_DIR}

    # Install required packages
    sudo pacman -S --noconfirm sbsigntools efitools mokutil

    # Generate Machine Owner Key (MOK)
    openssl req -new -x509 -newkey rsa:2048 -keyout ${MOK_KEY} -out ${MOK_CRT} -nodes -days 3650 -subj "/CN=Secure Boot MOK/"

    # Convert keys to EFI signature list format
    openssl x509 -in ${MOK_CRT} -outform DER -out ${MOK_CER}
    cert-to-efi-sig-list ${MOK_CER} ${MOK_ESL}

    # Create a hash of the signature list
    sign-efi-sig-list -k ${MOK_KEY} -c ${MOK_CRT} MOK ${MOK_ESL} ${MOK_AUTH}

    # Enroll the MOK
    sudo mokutil --import ${MOK_CER}

    echo "You will need to reboot and enroll the MOK using the password you set."

    # Sign the kernel and bootloader
    sudo sbsign --key ${MOK_KEY} --cert ${MOK_CRT} --output ${KERNEL_PATH} ${KERNEL_PATH}
    sudo sbsign --key ${MOK_KEY} --cert ${MOK_CRT} --output ${GRUB_PATH} ${GRUB_PATH}

    # Update GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    echo "Kernel and bootloader signed. Please reboot and enroll the MOK."
}

# Function to configure secure boot on Debian/Ubuntu
configure_debian_secure_boot() {
    echo "Configuring Secure Boot on Debian/Ubuntu..."

    # Install the necessary packages
    sudo apt update
    sudo apt install -y shim-signed grub-efi-amd64-signed

    # Generate your own keys
    mkdir -p ~/secure-boot
    cd ~/secure-boot
    openssl req -new -x509 -newkey rsa:2048 -keyout MOK.key -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=My Secure Boot Key"

    # Enroll the key
    sudo mokutil --import MOK.der

    # Sign the kernel and bootloader
    sudo sbsign --key MOK.key --cert MOK.der /boot/vmlinuz-$(uname -r) --output /boot/vmlinuz-$(uname -r).signed
    sudo cp /boot/vmlinuz-$(uname -r) /boot/vmlinuz-$(uname -r).backup
    sudo mv /boot/vmlinuz-$(uname -r).signed /boot/vmlinuz-$(uname -r)

    # Configure GRUB to use the signed kernel
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub

    # Update GRUB configuration
    sudo update-grub

    echo "Secure Boot configuration complete. Please reboot your system to enroll the key."
}


# Function to install packages using apt (Debian-based)
install_debian_packages() {

    if is_surface; then
        echo "Microsoft Surface device detected. Proceeding with Surface support installation for Debian Linux..."
        install_debian_surface_support
    fi

    configure_debian_secure_boot

}

# Function to install packages using pacman (Arch-based)
install_arch_packages() {
    
    if is_surface; then
        echo "Microsoft Surface device detected. Proceeding with Surface support installation for Arch Linux..."
        install_arch_surface_support
    fi
    
    configure_arch_secure_boot
}


if command -v apt-get >/dev/null 2>&1; then
    install_debian_packages
elif command -v pacman >/dev/null 2>&1; then
    install_yay
    install_arch_packages
else
    echo "Unsupported OS. Exiting."
    exit 1
fi