#!/bin/bash
# set -e command in a bash script is used to make the script exit immediately if any 
# command within the script returns a non-zero exit status
set -e

# run by bash <(curl -s https://gitlab.com/stephan-raabe/dotfiles/-/raw/main/setup.sh)




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
    # Install necessary packages including mokutil
    sudo pacman -S --needed --noconfirm efitools sbsigntool openssl mokutil
}

# Function to generate keys using OpenSSL
SecureBoot.generate_keys() {
    # Generate Secure Boot keys
    mkdir -p "${SecureBoot[cert_dir]}"

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
    sudo efi-updatevar -e -f "${SecureBoot[cert_dir]}/PK.cer" PK || { echo "Error: Failed to enroll PK key."; exit 1; }
    sudo efi-updatevar -e -f "${SecureBoot[cert_dir]}/KEK.cer" KEK || { echo "Error: Failed to enroll KEK key."; exit 1; }
    sudo efi-updatevar -e -f "${SecureBoot[cert_dir]}/DB.cer" db || { echo "Error: Failed to enroll DB key."; exit 1; }
    echo "Keys enrolled in UEFI firmware."
}

# Function to enroll MOK (Machine Owner Key)
SecureBoot.enroll_mok() {
    # Generate a MOK key
    openssl req -new -x509 -newkey rsa:2048 -keyout "${SecureBoot[cert_dir]}/MOK.key" -out "${SecureBoot[cert_dir]}/MOK.crt" -nodes -subj "/CN=MOK Key/"
    openssl x509 -in "${SecureBoot[cert_dir]}/MOK.crt" -outform DER -out "${SecureBoot[cert_dir]}/MOK.cer"

    # Enroll MOK
    echo "Please enter a password for the MOK enrollment process:"
    sudo mokutil --import "${SecureBoot[cert_dir]}/MOK.cer" || { echo "Error: Failed to enroll MOK key."; exit 1; }

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
    SecureBoot.install_dependencies
    SecureBoot.generate_keys
    SecureBoot.enroll_keys
    SecureBoot.enroll_mok
    SecureBoot.sign_files
    SecureBoot.update_grub_config
    SecureBoot.print_mok_instructions

    echo "Secure Boot setup completed successfully."
}


# Function to install yay if it is not already installed
install_yay() {
    if ! command -v yay &> /dev/null; then
        echo "yay not found, installing yay..."
        sudo pacman -S --needed --noconfirm git base-devel
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
    sudo pacman -S --needed --noconfirm linux-surface linux-surface-headers iptsd
    
    # Install additional firmware package for WiFi if needed
    local model=$(cat /sys/devices/virtual/dmi/id/product_name)
    case $model in
        *Surface*Pro*4|*Surface*Pro*5|*Surface*Pro*6|*Surface*Book*1|*Surface*Book*2|*Surface*Laptop*1|*Surface*Laptop*2)
            sudo pacman -S --needed --noconfirm linux-firmware-marvell
            ;;
    esac
    
    # Install the secure boot key if secure boot is set up
    read -p "Have you set up secure boot for Arch via SHIM? (y/N): " secureboot_setup
    if [[ $secureboot_setup =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed --noconfirm linux-surface-secureboot-mok
        echo "Please reboot and enroll the key by following the on-screen instructions. Use the password 'surface'."
    else
        echo "Secure boot not set up. Skipping secure boot key installation."
    fi
    
    # Update GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    
    echo "Installation complete. Please reboot your system."
}

install_video_drivers() {
    echo "Detect VGA compatible controllers..."
    vga_controllers=$(lspci | grep VGA)

    # Check if there are any VGA controllers found
    if [[ -z "$vga_controllers" ]]; then
        echo "No VGA compatible controllers found."
        return 1
    fi

    # Install drivers based on detected controllers
    if echo "$vga_controllers" | grep -qi "NVIDIA"; then
        echo "Detected NVIDIA VGA controller. Installing NVIDIA drivers..."
        sudo pacman -S --needed --noconfirm nvidia
    fi

    if echo "$vga_controllers" | grep -qi "AMD"; then
        echo "Detected AMD VGA controller. Installing AMD drivers..."
        sudo pacman -S --needed --noconfirm xf86-video-amdgpu mesa
    fi

    if echo "$vga_controllers" | grep -qi "Intel"; then
        echo "Detected Intel VGA controller. Installing Intel drivers..."
        sudo pacman -S --needed --noconfirm xf86-video-intel mesa
    fi

    # Additional handling for hybrid graphics (NVIDIA Optimus)
    # Install bumblebee for NVIDIA Optimus laptops
    # if lspci | grep -qi "VGA compatible controller: NVIDIA"; then
    #     echo "Detected NVIDIA GPU for hybrid graphics (NVIDIA Optimus). Installing Bumblebee..."
    #     sudo pacman -S bumblebee
    # fi

    # Additional configurations as needed (Xorg, etc.)
    # Add your additional configuration steps here if required

    echo "Video Driver installation complete."
}
# Class-like structure for Hyprland setup
HyprlandSetup() {
    # Variables
    local config_file="$HOME/.config/hypr/hyprland.conf"
    local desktop_file="/usr/share/wayland-sessions/hyprland.desktop"
    local config_dir="$HOME/.config/hypr"
    local config_file="$config_dir/hyprland.conf"

    # Initialize function
    initialize() {
        echo "--> Setting up Hyprland"        
        echo "Ensure the configuration directory exists"
        mkdir -p "$(dirname "$config_file")"
    }

    # Install Hyprland and wlr-randr
    install() {
        echo "Installing Hyprland and wlr-randr..."
        sudo pacman -S --needed --noconfirm sddm hyprland wlr-randr wofi waybar
        echo "Hyprland and wlr-randr installation complete."
    }

    # Detect the highest resolution supported by the primary monitor using wlr-randr
    detect_highest_resolution() {
        echo "Setting up resolution in Hyprland..."
        # https://wiki.hyprland.org/Configuring/Multi-GPU/
        highest_resolution=$(wlr-randr | grep '^\s\+[0-9]\+x[0-9]\+' | awk '{print $1}' | sort -r | head -n 1)
        monitor=$(wlr-randr | grep '^\s*' | grep -B1 "$highest_resolution" | head -n 1 | awk '{print $1}')
        
        if [[ -z "$highest_resolution" || -z "$monitor" ]]; then
            echo "Could not detect the highest resolution."
            return 1
        fi

        echo "Detected highest resolution: $highest_resolution for monitor: $monitor"
        echo "$monitor $highest_resolution"
    }

    # Configure highest resolution in Hyprland
    configure_highest_resolution() {
        # Detect the highest resolution 
        # show all monitors (https://wiki.hyprland.org/Configuring/Monitors/): hyprctl monitors all
        resolution_info=$(detect_highest_resolution)
        if [[ $? -ne 0 ]]; then
            echo "Failed to detect highest resolution. Exiting."
            return 1
        fi

        monitor=$(echo "$resolution_info" | awk '{print $1}')
        resolution=$(echo "$resolution_info" | awk '{print $2}')

        # Add the highest resolution setting if it does not already exist
        if ! grep -q "^monitor = $monitor, $resolution" "$config_file"; then
            echo "Setting highest resolution in Hyprland configuration..."
            echo "monitor = $monitor, $resolution@60, 0x0" >> "$config_file"
        else
            echo "Highest resolution already set in Hyprland configuration."
        fi
    }

    # Create .desktop file and set Hyprland as default session
    configure_default_session() {
        # Create the .desktop file for Hyprland
        echo "Creating Hyprland .desktop file..."
        echo "Enabling SDDM service..."
        sudo systemctl enable sddm.service --now
    
        echo "Setting up Hyprland wrapper script..."
        mkdir -p ~/.local/bin

        cat << 'EOF' > ~/.local/bin/wrappedhl
#!/bin/sh

cd ~

# Log WLR errors and logs to the hyprland log. Recommended
export HYPRLAND_LOG_WLR=1

# Tell XWayland to use a cursor theme
export XCURSOR_THEME=Bibata-Modern-Classic

# Set a cursor size
export XCURSOR_SIZE=24

# Example IME Support: fcitx
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus

exec Hyprland
EOF
        chmod +x ~/.local/bin/wrappedhl
        
        echo "Creating custom Hyprland session file..."
        sudo cp /usr/share/wayland-sessions/hyprland.desktop /usr/share/wayland-sessions/hyprland-wrapped.desktop
        sudo sed -i 's|Exec=Hyprland|Exec=/home/$USER/.local/bin/wrappedhl|' /usr/share/wayland-sessions/hyprland-wrapped.desktop
        
        echo "Done creating custom Hyprland session file."
    }


    # Function to add or modify key binding for showing all bindings
    add_show_bindings_key() {
        local key_combination="Mod4+slash"  # Modify as needed

        # Check if the config directory exists, create if not
        if [ ! -d "$config_dir" ]; then
            mkdir -p "$config_dir"
        fi

    # Create or append to the bindings script using a heredoc
    cat > "$config_dir/show_bindings.sh" <<EOF
#!/bin/bash

# Define the path to the Hyprland configuration file
CONFIG_FILE="$config_file"

# Extract key bindings from the configuration file
bindings=\$(grep -E "bind[ ]*=" "\$CONFIG_FILE")

# Display key bindings using wofi
wofi --show dmenu --prompt "Hyprland Key Bindings" <<< "\$bindings"
EOF

        # Make the script executable
        chmod +x "$config_dir/show_bindings.sh"

        # Check if the key combination already exists in the config file
        if grep -qE "bind[ ]*=[ ]*${key_combination}" "$config_file"; then
            # If exists, comment out the old binding
            sed -i "/bind[ ]*=[ ]*${key_combination}/ s/^/#/" "$config_file"
        fi

        # Append the new binding to show all bindings
        echo "bind = $key_combination exec $config_dir/show_bindings.sh" >> "$config_file"

        echo "Key binding for showing all bindings added or updated."
        echo "Restart Hyprland or reload its configuration for changes to take effect."
    }

    # Function to update or add a setting in the configuration file
    update_or_add_setting() {
        local setting_name="$1"
        local setting_value="$2"
        
        if grep -q "^$setting_name =" "$config_file"; then
            sed -i "s/^$setting_name =.*/$setting_name = $setting_value/" "$config_file"
            echo "Updated $setting_name in Hyprland configuration."
        else
            echo "$setting_name = $setting_value" >> "$config_file"
            echo "Added $setting_name to Hyprland configuration."
        fi
    }

    # Configure Hyprland with specified settings if they don't already exist
    configure_hyprland() {
        # Path to Hyprland configuration file
        # local config_file="$HOME/.config/hypr/hyprland.conf"

        # Ensure the configuration directory exists
        mkdir -p "$(dirname "$config_file")"

        # Remove the autogenerated line to eliminate the yellow warning if it exists
        if grep -q "^autogenerated=1" "$config_file"; then
            echo "Removing autogenerated=1 from Hyprland configuration..."
            sed -i '/^autogenerated=1/d' "$config_file"
        fi

        # Update or add settings to Hyprland configuration file
        echo "Configuring Hyprland settings in $config_file..."

        # Function to update or add a setting in the configuration file
        update_or_add_setting() {
            local setting_name="$1"
            local setting_value="$2"
            
            if grep -q "^$setting_name =" "$config_file"; then
                sed -i "s/^$setting_name =.*/$setting_name = $setting_value/" "$config_file"
                echo "Updated $setting_name in Hyprland configuration."
            else
                echo "$setting_name = $setting_value" >> "$config_file"
                echo "Added $setting_name to Hyprland configuration."
            fi
        }

       # Example settings to configure
        update_or_add_setting "sensitivity" "1.0"
        update_or_add_setting "border_size" "3"
        update_or_add_setting "gaps_in" "2"
        update_or_add_setting "gaps_out" "2"
        update_or_add_setting "col.inactive_border" "gradient(0xff444444)"
        update_or_add_setting "col.active_border" "gradient(0xffffffff)"
        update_or_add_setting "col.nogroup_border" "gradient(0xffffaaff)"
        update_or_add_setting "col.nogroup_border_active" "gradient(0xffff00ff)"
        update_or_add_setting "layout" "dwindle"
        update_or_add_setting "no_focus_fallback" "false"
        update_or_add_setting "apply_sens_to_raw" "false"
        update_or_add_setting "resize_on_border" "false"
        update_or_add_setting "extend_border_grab_area" "15"
        update_or_add_setting "hover_icon_on_border" "true"
        update_or_add_setting "allow_tearing" "false"
        update_or_add_setting "resize_corner" "0"

        # Example decoration settings
        update_or_add_setting "rounding" "0"
        update_or_add_setting "active_opacity" "1.0"
        update_or_add_setting "inactive_opacity" "1.0"
        update_or_add_setting "fullscreen_opacity" "1.0"
        update_or_add_setting "drop_shadow" "true"
        update_or_add_setting "shadow_range" "4"
        update_or_add_setting "shadow_render_power" "3"
        update_or_add_setting "shadow_ignore_window" "true"
        update_or_add_setting "col.shadow" "color(0xee1a1a1a)"
        update_or_add_setting "shadow_offset" "[0, 0]"
        update_or_add_setting "shadow_scale" "1.0"
        update_or_add_setting "dim_inactive" "false"
        update_or_add_setting "dim_strength" "0.5"
        update_or_add_setting "dim_special" "0.2"
        update_or_add_setting "dim_around" "0.4"
        update_or_add_setting "screen_shader" "[[Empty]]"

        # Example blur settings
        update_or_add_setting "decoration:blur.enabled" "true"
        update_or_add_setting "decoration:blur.size" "8"
        update_or_add_setting "decoration:blur.passes" "1"
        update_or_add_setting "decoration:blur.ignore_opacity" "false"
        update_or_add_setting "decoration:blur.new_optimizations" "true"
        update_or_add_setting "decoration:blur.xray" "false"
        update_or_add_setting "decoration:blur.noise" "0.0117"
        update_or_add_setting "decoration:blur.contrast" "0.8916"
        update_or_add_setting "decoration:blur.brightness" "0.8172"
        update_or_add_setting "decoration:blur.vibrancy" "0.1696"
        update_or_add_setting "decoration:blur.vibrancy_darkness" "0.0"
        update_or_add_setting "decoration:blur.special" "false"
        update_or_add_setting "decoration:blur.popups" "false"
        update_or_add_setting "decoration:blur.popups_ignorealpha" "0.2"


        echo "Hyprland configuration updated."
    }
    # Run all setup functions
    run() {
        initialize
        install
        configure_highest_resolution
        configure_default_session
        configure_hyprland
        add_show_bindings_key
        echo "Hyprland setup complete."
    }

    # Expose functions
    case "$1" in
        initialize) initialize ;;
        install) install ;;
        detect_highest_resolution) detect_highest_resolution ;;
        configure_highest_resolution) configure_highest_resolution ;;
        configure_default_session) configure_default_session ;;
        configure_hyprland) configure_hyprland ;;
        run) run ;;
        *) echo "Invalid command. Use initialize, install, detect_highest_resolution, configure_highest_resolution, configure_default_session, configure_hyprland, or run." ;;
    esac
}

#!/bin/bash

function switch_to_sddm() {
    
    echo "Switching to sddm..."
    # Array of known display managers
    local display_managers=("gdm" "lightdm" "lxdm" "xorg-xdm")
    
    echo "Uninstalling known display managers..."
    for dm in "${display_managers[@]}"; do
        if pacman -Q $dm &> /dev/null; then
            echo "Removing $dm..."
            sudo pacman -Rns --noconfirm $dm
        else
            echo "$dm is not installed."
        fi
    done
    
    echo "Installing SDDM..."
    sudo pacman -S --noconfirm sddm
    
    echo "Disabling any currently running display manager services..."
    for dm in "${display_managers[@]}"; do
        sudo systemctl disable $dm.service --now 2>/dev/null
    done
    
    echo "Enabling SDDM service..."
    sudo systemctl enable sddm.service --now
    
    echo "SDDM has been installed and set as the default display manager."
}


main() {
    sudo pacman-key --init
    sudo pacman-key --populate archlinux

    sudo pacman -Syu
    install_yay

    install_video_drivers
    switch_to_sddm

    if is_surface; then
        echo "Microsoft Surface device detected. Proceeding with Surface support installation for Arch Linux..."
        install_arch_surface_support
    fi
    
    HyprlandSetup run

    sudo pacman -S --needed --noconfirm  keepassxc kitty
    sudo yay -S --needed --noconfirm logseq-desktop

    # never got this to work more debuggin needed
    # SecureBoot.run
}

main