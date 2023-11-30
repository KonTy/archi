#!/bin/bash
SCRIPTHOME_DIR=archi
# Checking if is running in Repo Folder
if [[ "$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')" =~ ^scripts$ ]]; then
    echo "You are running this in ${SCRIPTHOME_DIR} Folder."
    exit
fi

# Installing git
cd $HOME
echo "Installing git."
pacman -Sy --noconfirm --needed git glibc

echo "Cloning the ${SCRIPTHOME_DIR} Project"
git clone https://github.com/KonTy/archi

echo "Change directory to $HOME/$SCRIPT_DIR"
cd "$HOME/$SCRIPT_DIR"


echo "Current directory is $pwd Executing ${SCRIPTHOME_DIR} Script"
exec ./archi.sh
