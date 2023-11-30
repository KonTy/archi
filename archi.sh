#!/bin/bash
set -a
SCRIPT_DIR=$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"
# Extract only the last directory without the full path
SCRIPTHOME_DIR=$(basename "$SCRIPT_DIR")
set +a

log_to_file() {
    local log_file="all-scripts.log"

    script_name=$(echo "$line" | sed -n 's/.*(\(.*\))/\1/p')
    awk -v script="$(basename "$0")" '{ print strftime("[%Y-%m-%d %H:%M:%S]"), "[" script_name "]:", $0 }' >> "$log_file"
}


cd "$SCRIPT_DIR"

(bash $SCRIPTS_DIR/startup.sh) 2>&1 | log_to_file
source $CONFIGS_DIR/setup.conf
(bash $SCRIPTS_DIR/0-preinstall.sh) 2>&1 | log_to_file

# now modify actual installation
# (arch-chroot /mnt "$SCRIPTS_DIR/1-setup.sh") 2>&1 | log_to_file

#if [["$DESKTOP_ENV" != "server"]]; then
#  (arch-chroot /mnt /usr/bin/runuser -u $USERNAME -- $SCRIPTS_DIR/2-user.sh ) |& log_to_file
#fi

#(arch-chroot /mnt "$SCRIPTS_DIR/3-post-setup.sh") |& log_to_file
#cp -v *.log /mnt/home/$USERNAME