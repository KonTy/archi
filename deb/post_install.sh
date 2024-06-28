#!/bin/sh

# Function to install packages using apt (Debian-based)
install_debian_packages() {
    echo "deb [arch=amd64] https://packages.surfacelinux.com/debian release main" > /etc/apt/sources.list.d/surface.list
    curl -s https://packages.surfacelinux.com/debian/public.key | apt-key add -
    apt-get update
    apt-get install -y linux-image-surface linux-headers-surface iptsd libwacom-surface
}

# Function to install packages using pacman (Arch-based)
install_arch_packages() {
    echo "[surface]
Server = https://pkg.surfacelinux.com/arch/ /" | tee /etc/pacman.d/surface-mirrorlist
    echo "[surface]
Include = /etc/pacman.d/surface-mirrorlist" | tee -a /etc/pacman.conf
    pacman -Syu
    pacman -S linux-surface linux-surface-headers iptsd libwacom-surface
}

# Function to install packages using yay (Arch-based with AUR helper)
install_arch_packages_with_yay() {
    echo "[surface]
Server = https://pkg.surfacelinux.com/arch/ /" | sudo tee /etc/pacman.d/surface-mirrorlist
    echo "[surface]
Include = /etc/pacman.d/surface-mirrorlist" | sudo tee -a /etc/pacman.conf
    yay -Syu
    yay -S linux-surface linux-surface-headers iptsd libwacom-surface
}

# Check if running on a Surface Laptop 4 or above
if dmidecode -s system-product-name | grep -q "Surface Laptop [4-9]"; then
    echo "Surface Laptop 4 or above detected. Installing necessary binaries..."

    if command -v apt-get >/dev/null 2>&1; then
        install_debian_packages
    elif command -v yay >/dev/null 2>&1; then
        install_arch_packages_with_yay
    elif command -v pacman >/dev/null 2>&1; then
        install_arch_packages
    else
        echo "Unsupported OS. Exiting."
        exit 1
    fi
else
    echo "Not a Surface Laptop 4 or above. Skipping Surface-specific installations."
fi

