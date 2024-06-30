#!/bin/bash

# Function to detect if the current machine is a Microsoft Surface device
is_surface() {
    local model=$(cat /sys/devices/virtual/dmi/id/product_name)
    case $model in
        *Surface*) return 0 ;;  # If the model name contains "Surface", it's a Surface device
        *) return 1 ;;
    esac
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


install_debian_packages
