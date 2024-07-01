#!/bin/bash
# set -e command in a bash script is used to make the script exit immediately if any 
# command within the script returns a non-zero exit status
set -e

# Define an associative array to simulate class properties
declare -A SecureBoot

# Initialize function to set up SecureBoot properties
SecureBoot.initialize() {
    # Initialize properties
    SecureBoot[cert_dir]="/etc/secureboot"
    SecureBoot[bootloader]="/boot/EFI/BOOT/bootx64.efi"
    SecureBoot[kernel]="/boot/vmlinuz-linux"
    SecureBoot[initramfs]="/boot/initramfs-linux.img"
    SecureBoot[grub_cfg]="/boot/grub/grub.cfg"
}

# Function to install required packages
SecureBoot.install_dependencies() {
    echo "Installing necessary packages including efitools, openssl, and mokutil..."
    sudo pacman -S --needed --noconfirm efitools openssl mokutil
  
    echo "Installing sbsigntool"
    sudo pacman -S --needed --noconfirm sbsigntools

    echo "Packages installed."
}

# Function to generate keys using OpenSSL
SecureBoot.generate_keys() {
    echo "Generating Secure Boot keys..."
    sudo mkdir -p "${SecureBoot[cert_dir]}"

    openssl req -new -x509 -newkey rsa:2048 -keyout "${SecureBoot[cert_dir]}/DB.key" -out "${SecureBoot[cert_dir]}/DB.crt" -nodes -subj "/CN=DB Key/"
    openssl req -new -x509 -newkey rsa:2048 -keyout "${SecureBoot[cert_dir]}/KEK.key" -out "${SecureBoot[cert_dir]}/KEK.crt" -nodes -subj "/CN=KEK Key/"
    openssl req -new -x509 -newkey rsa:2048 -keyout "${SecureBoot[cert_dir]}/PK.key" -out "${SecureBoot[cert_dir]}/PK.crt" -nodes -subj "/CN=PK Key/"

    # Convert keys to DER format
    openssl x509 -in "${SecureBoot[cert_dir]}/DB.crt" -outform DER -out "${SecureBoot[cert_dir]}/DB.cer"
    openssl x509 -in "${SecureBoot[cert_dir]}/KEK.crt" -outform DER -out "${SecureBoot[cert_dir]}/KEK.cer"
    openssl x509 -in "${SecureBoot[cert_dir]}/PK.crt" -outform DER -out "${SecureBoot[cert_dir]}/PK.cer"

    echo "Keys generated and converted to DER format."
}

# Function to enroll keys in UEFI firmware
SecureBoot.enroll_keys() {
    echo "Enrolling keys in UEFI firmware..."
    sudo efi-updatevar -e -f "${SecureBoot[cert_dir]}/PK.cer" PK
    sudo efi-updatevar -e -f "${SecureBoot[cert_dir]}/KEK.cer" KEK
    sudo efi-updatevar -e -f "${SecureBoot[cert_dir]}/DB.cer" db
    echo "Keys enrolled in UEFI firmware."
}

# Function to enroll MOK (Machine Owner Key)
SecureBoot.enroll_mok() {
    echo "Enrolling MOK (Machine Owner Key)..."
    # Generate a MOK key
    openssl req -new -x509 -newkey rsa:2048 -keyout "${SecureBoot[cert_dir]}/MOK.key" -out "${SecureBoot[cert_dir]}/MOK.crt" -nodes -subj "/CN=MOK Key/"
    openssl x509 -in "${SecureBoot[cert_dir]}/MOK.crt" -outform DER -out "${SecureBoot[cert_dir]}/MOK.cer"

    # Enroll MOK
    echo "Please enter a password for the MOK enrollment process:"
    sudo mokutil --import "${SecureBoot[cert_dir]}/MOK.cer"

    echo "After rebooting, follow the instructions to enroll the MOK in the firmware."

    # Sign bootloader and kernel with MOK
    sbsign --key "${SecureBoot[cert_dir]}/MOK.key" --cert "${SecureBoot[cert_dir]}/MOK.crt" --output "${SecureBoot[bootloader]}.signed" "${SecureBoot[bootloader]}"
    sbsign --key "${SecureBoot[cert_dir]}/MOK.key" --cert "${SecureBoot[cert_dir]}/MOK.crt" --output "${SecureBoot[kernel]}.signed" "${SecureBoot[kernel]}"
    sbsign --key "${SecureBoot[cert_dir]}/MOK.key" --cert "${SecureBoot[cert_dir]}/MOK.crt" --output "${SecureBoot[initramfs]}.signed" "${SecureBoot[initramfs]}"

    # Move signed files to appropriate locations
    sudo mv "${SecureBoot[bootloader]}.signed" "${SecureBoot[bootloader]}"
    sudo mv "${SecureBoot[kernel]}.signed" "${SecureBoot[kernel]}"
    sudo mv "${SecureBoot[initramfs]}.signed" "${SecureBoot[initramfs]}"

    echo "MOK keys generated, enrolled, and files signed. Please reboot and enroll the MOK in your UEFI firmware."
}

# Function to sign bootloader and kernel
SecureBoot.sign_files() {
    echo "Signing bootloader and kernel..."
    sbsign --key "${SecureBoot[cert_dir]}/DB.key" --cert "${SecureBoot[cert_dir]}/DB.crt" --output "${SecureBoot[bootloader]}.signed" "${SecureBoot[bootloader]}"
    sbsign --key "${SecureBoot[cert_dir]}/DB.key" --cert "${SecureBoot[cert_dir]}/DB.crt" --output "${SecureBoot[kernel]}.signed" "${SecureBoot[kernel]}"
    sbsign --key "${SecureBoot[cert_dir]}/DB.key" --cert "${SecureBoot[cert_dir]}/DB.crt" --output "${SecureBoot[initramfs]}.signed" "${SecureBoot[initramfs]}"

    # Move signed files to appropriate locations
    sudo mv "${SecureBoot[bootloader]}.signed" "${SecureBoot[bootloader]}"
    sudo mv "${SecureBoot[kernel]}.signed" "${SecureBoot[kernel]}"
    sudo mv "${SecureBoot[initramfs]}.signed" "${SecureBoot[initramfs]}"

    echo "Bootloader and kernel signed."
}

# Function to update GRUB configuration to use signed kernel
SecureBoot.update_grub_config() {
    echo "Updating GRUB configuration to use signed kernel..."
    # Backup existing GRUB config
    sudo cp "${SecureBoot[grub_cfg]}" "${SecureBoot[grub_cfg]}.bak"

    # Update GRUB config to use signed kernel
    sudo sed -i "s|vmlinuz-linux|vmlinuz-linux.signed|g" "${SecureBoot[grub_cfg]}"
    sudo sed -i "s|initramfs-linux.img|initramfs-linux.img.signed|g" "${SecureBoot[grub_cfg]}"

    echo "GRUB configuration updated."
}

# Function to print final instructions for MOK enrollment
SecureBoot.print_mok_instructions() {
    echo
    echo "=== MOK Enrollment Instructions ==="
    echo "1. Reboot your system."
    echo "2. During boot, enter the BIOS/UEFI settings by pressing a specific key (F2, F10, Delete, or Esc)."
    echo "3. Navigate to the Secure Boot settings."
    echo "4. Find an option typically labeled as 'Enroll MOK' or 'Enroll Key'."
    echo "5. Browse to the location where the MOK certificate (MOK.cer) is stored:"
    echo "   ${SecureBoot[cert_dir]}/MOK.cer"
    echo "6. Select the MOK certificate (MOK.cer) and follow the on-screen instructions to enroll it."
    echo "7. Set a password when prompted."
    echo "8. After enrollment, save your changes and exit the BIOS/UEFI settings."
    echo "9. Your system will now boot with Secure Boot enabled using the enrolled MOK key."
    echo "==================================="
    echo
}

# Function to prompt and confirm Setup Mode
SecureBoot.confirm_setup_mode() {
    echo "Before proceeding, please ensure you have switched your system to Setup Mode in the BIOS/UEFI settings."
    read -p "Have you switched to Setup Mode? (y/n): " choice
    case "$choice" in
        y|Y ) ;;
        * ) echo "Please switch to Setup Mode and rerun the script."; exit 1;;
    esac
}


# Main function to execute the setup
SecureBoot.run() {

    SecureBoot.confirm_setup_mode
    
    SecureBoot.initialize
    echo "Initialized SecureBoot properties."

    SecureBoot.install_dependencies
    echo "Installed necessary packages."

    SecureBoot.generate_keys
    echo "Generated Secure Boot keys."

    SecureBoot.enroll_keys
    echo "Enrolled keys in UEFI firmware."

    SecureBoot.enroll_mok
    echo "Enrolled MOK (Machine Owner Key) and signed bootloader and kernel."

    SecureBoot.sign_files
    echo "Signed bootloader and kernel with DB keys."

    SecureBoot.update_grub_config
    echo "Updated GRUB configuration to use signed kernel."

    SecureBoot.print_mok_instructions
    echo "Printed MOK enrollment instructions."

    echo "Secure Boot setup completed. Please reboot your system to apply the changes."
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

main() {
    sudo pacman-key --init
    sudo pacman-key --populate archlinux

    sudo pacman -Syu

    install_yay

    if is_surface; then
        echo "Microsoft Surface device detected. Proceeding with Surface support installation for Arch Linux..."
        install_arch_surface_support
    fi

    SecureBoot.run
}

main