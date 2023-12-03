#!/bin/bash
set -a
SCRIPT_DIR=$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"
# Extract only the last directory without the full path
SCRIPTHOME_DIR="${SCRIPT_DIR##*/}"
set +a

echo "All variables are set"


# Output file
output_file="output.log"

echo "Script dir is $SCRIPT_DIR cd into it"
cd "$SCRIPT_DIR"

echo "Launching start up..."
( bash $SCRIPTS_DIR/startup.sh ) 2>&1 | tee -a "$output_file"
source $CONFIGS_DIR/setup.conf
( bash $SCRIPTS_DIR/0-preinstall.sh ) 2>&1 | tee -a "$output_file"
( arch-chroot /mnt $SCRIPTS_DIR/1-setup.sh ) 2>&1 | tee -a "$output_file"

echo "Desktop Environment is $DESKTOP_ENV" 2>&1 | tee -a "$output_file"
chmod +x $SCRIPTS_DIR/2-user.sh
if [[ "$DESKTOP_ENV" != "server" ]]; then
    
    echo "Running as $USERNAME script: $SCRIPTS_DIR/2-user.sh" 2>&1 | tee -a "$output_file"
    
    (arch-chroot /mnt /usr/bin/runuser -u $USERNAME /home/$USERNAME/archi/scripts/2-user.sh) > >(tee -a "$output_file") 2> >(tee -a "$output_file" >&2)

    # if ! (arch-chroot /mnt /usr/bin/runuser -u $USERNAME $SCRIPTS_DIR/2-user.sh) > >(tee -a "$output_file") 2> >(tee -a "$output_file" >&2); then
    #     echo "Permission denied error. Check $output_file for details."
    #     exit
    # fi
#    ( arch-chroot /mnt /usr/bin/runuser -u $USERNAME -- $SCRIPTS_DIR/2-user.sh ) 2>&1 | tee -a "$output_file"
fi
( arch-chroot /mnt $SCRIPTS_DIR/3-post-setup.sh ) 2>&1 | tee -a "$output_file"