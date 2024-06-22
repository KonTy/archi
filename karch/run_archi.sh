#!/bin/bash
set -a
SCRIPT_DIR=$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"
# Extract only the last directory without the full path
SCRIPTHOME_DIR="${SCRIPT_DIR##*/}"
# Use free command to get total available memory
TOTAL_RAM=$(free -m | awk '/^Mem:/ {print $2}')
# Set RAM_SIZE to be equal to total available RAM
RAM_SIZE="${TOTAL_RAM}M"

set +a

echo "All variables are set"


# Output file
output_file="archi.log"

echo "Script dir is $SCRIPT_DIR cd into it"
cd "$SCRIPT_DIR"

echo "Launching start up..."
( bash $SCRIPTS_DIR/startup.sh ) 2>&1 | tee -a "$output_file"
source $CONFIGS_DIR/setup.conf

# adding more debug info
( stdbuf -oL bash -x $SCRIPTS_DIR/0-preinstall.sh ) 2>&1 | tee -a "$output_file"
# ( bash $SCRIPTS_DIR/0-preinstall.sh ) 2>&1 | tee -a "$output_file"


echo -ne "
-------------------------------------------------------------------------
                   EXITING NOW
-------------------------------------------------------------------------
"
exit


( arch-chroot /mnt $SCRIPTS_DIR/1-setup.sh ) 2>&1 | tee -a "$output_file"

echo "Desktop Environment is $DESKTOP_ENV" 2>&1 | tee -a "$output_file"
if [[ "$DESKTOP_ENV" != "server" ]]; then
    echo "**** Running as $USERNAME script: /home/$USERNAME/$SCRIPTHOME_DIR/scripts/2-user.sh" 2>&1 | tee -a "$output_file"
    (arch-chroot /mnt /usr/bin/runuser -u $USERNAME /home/$USERNAME/$SCRIPTHOME_DIR/scripts/2-user.sh) > >(tee -a "$output_file") 2> >(tee -a "$output_file" >&2)
fi

( arch-chroot /mnt $SCRIPTS_DIR/3-post-setup.sh ) 2>&1 | tee -a "$output_file"