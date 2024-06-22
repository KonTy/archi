#!/usr/bin/env bash
#github-action genshdoc
#
source ${HOME}/${SCRIPTHOME_DIR}/configs/setup.conf

if [[ -d "/sys/firmware/efi" ]]; then
    grub-install --efi-directory=/boot ${DISK}
fi

echo -ne "
-------------------------------------------------------------------------
               Enabling (and Theming) Login Display Manager
-------------------------------------------------------------------------
"
if [[ ${DESKTOP_ENV} == "kde" ]]; then
  systemctl enable sddm.service
  if [[ ${INSTALL_TYPE} == "FULL" ]]; then
    echo [Theme] >>  /etc/sddm.conf
    echo Current=Nordic >> /etc/sddm.conf
  fi

elif [[ "${DESKTOP_ENV}" == "gnome" ]]; then
  systemctl enable gdm.service

else
  if [[ ! "${DESKTOP_ENV}" == "server"  ]]; then
  sudo pacman -S --noconfirm --needed lightdm lightdm-gtk-greeter
  systemctl enable lightdm.service
  fi
fi

echo -ne "
-------------------------------------------------------------------------
                    Enabling Essential Services
-------------------------------------------------------------------------
"
systemctl enable cups.service
echo "  Cups enabled"
ntpd -qg
systemctl enable ntpd.service
echo "  NTP enabled"
systemctl disable dhcpcd.service
echo "  DHCP disabled"
systemctl stop dhcpcd.service
echo "  DHCP stopped"
systemctl enable NetworkManager.service
echo "  NetworkManager enabled"
systemctl disable bluetooth
echo "  Bluetooth disabled"
systemctl enable avahi-daemon.service
echo "  Avahi enabled"

# if [[ "${FS}" == "luks" || "${FS}" == "btrfs" ]]; then
# echo -ne "
# -------------------------------------------------------------------------
#                     Creating Snapper Config
# -------------------------------------------------------------------------
# "

# SNAPPER_CONF="$HOME/${SCRIPTHOME_DIR}/configs/etc/snapper/configs/root"
# mkdir -p /etc/snapper/configs/
# cp -rfv ${SNAPPER_CONF} /etc/snapper/configs/

# SNAPPER_CONF_D="$HOME/${SCRIPTHOME_DIR}/configs/etc/conf.d/snapper"
# mkdir -p /etc/conf.d/
# cp -rfv ${SNAPPER_CONF_D} /etc/conf.d/

# fi

# echo -ne "
# -------------------------------------------------------------------------
#                Enabling (and Theming) Plymouth Boot Splash
# -------------------------------------------------------------------------
# "
# PLYMOUTH_THEMES_DIR="$HOME/${SCRIPTHOME_DIR}/configs/usr/share/plymouth/themes"
# PLYMOUTH_THEME="arch-glow" # can grab from config later if we allow selection
# mkdir -p /usr/share/plymouth/themes
# echo 'Installing Plymouth theme...'
# cp -rf ${PLYMOUTH_THEMES_DIR}/${PLYMOUTH_THEME} /usr/share/plymouth/themes
# if  [[ $FS == "luks"]]; then
#   sed -i 's/HOOKS=(base udev*/& plymouth/' /etc/mkinitcpio.conf # add plymouth after base udev
#   sed -i 's/HOOKS=(base udev \(.*block\) /&plymouth-/' /etc/mkinitcpio.conf # create plymouth-encrypt after block hook
# else
#   sed -i 's/HOOKS=(base udev*/& plymouth/' /etc/mkinitcpio.conf # add plymouth after base udev
# fi
# plymouth-set-default-theme -R arch-glow # sets the theme and runs mkinitcpio
# echo 'Plymouth theme installed'

echo -ne "
-------------------------------------------------------------------------
                    Cleaning
-------------------------------------------------------------------------
"
# Remove no password sudo rights
sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
# Add sudo rights
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

rm -r $HOME/${SCRIPTHOME_DIR}
rm -r /home/$USERNAME/${SCRIPTHOME_DIR}

# Replace in the same state
cd $pwd
