#!/bin/bash

# Installing git
cd ~
echo "Installing git."
pacman -Sy --noconfirm --needed git glibc

echo "Cloning the archi Project"
git clone https://github.com/KonTy/archi

echo "Change directory to ~/$SCRIPTHOME_DIR"
cd $HOME/archi

echo "Current directory is $(pwd) Executing Script"
exec ./archi_install.sh
