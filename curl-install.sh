#!/bin/bash

# Installing git
cd ~
echo "Installing git."
pacman -Sy --noconfirm --needed git glibc dialog

echo "Cloning the archi Project"
git clone https://github.com/KonTy/archi

echo "Change directory to ~/$SCRIPTHOME_DIR"
cd $HOME/archi

echo "Current directory is $(pwd) Executing Script"
exec ./run_archi.sh
