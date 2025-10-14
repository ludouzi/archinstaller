#!/bin/bash

set -euo pipefail

source config/variables.sh

################################################################################
# Functions
################################################################################

get_partition_path() {
    local disk="$1"
    local part="$2"

    if [[ "$disk" == /dev/nvme* ]] || [[ "$disk" == /dev/mmcblk* ]]; then
        echo "${disk}p${part}"
    else
        echo "${disk}${part}"
    fi
}

select_disk() {   
    local selected_disk=$(lsblk -d -n -o NAME,SIZE,TYPE,MODEL | awk '
        $3 == "disk" && $1 !~ /^sr/ {
            disk_path = "/dev/" $1
            printf "%-12s %-8s %s\n", disk_path, $2, $4
        }' | fzf --height=40% --reverse --header="Select a disk:" | awk '{print $1}')
    
    if [[ -z "$selected_disk" ]]; then
        echo "No disk selected"
        return 1
    fi
    
    echo "$selected_disk"
}

select_partition() {
    local disk="$1"
    local description="$2"
    local out_result="$3"
    
    echo -e "\n[${B}INFO${W}] Select $description partition"
    
    # Get partitions and present with fzf
    local selected_partition=$(lsblk -l -o NAME,SIZE,TYPE,MOUNTPOINT "$disk" | \
        awk -v disk="$(basename "$disk")" 'NR>1 && $1 != disk && $3 == "part" {print $1 "\t" $2 "\t" $4}' | \
        fzf --height=40% --reverse --header="Select a $description partition:" | awk '{print $1}')
    
    if [[ -z "$selected_partition" ]]; then
        echo "Error: No partition selected"
        return 1
    fi
    
    # Convert partition name to full path
    local result=""
    if [[ "$disk" == /dev/nvme* ]] || [[ "$disk" == /dev/mmcblk* ]]; then
        result="/dev/$selected_partition"
    else
        # For regular disks, we need to extract the partition number
        local part_num=$(echo "$selected_partition" | sed "s/$(basename "$disk")//")
        result="${disk}${part_num}"
    fi
    
    eval $out_result=\$result
    echo "Selected: $result"
}

validate_disk() {
    local disk="$1"
    if [[ ! -b "$disk" ]]; then
        echo "Error: $disk is not a valid block device"
        return 1
    fi
    return 0
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    read -r -p "$message (y/N) " response
    response="${response:-$default}"
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

mount_with_check() {
    local partition="$1"
    local mount_point="$2"
    
    if ! mountpoint -q "$mount_point"; then
        mkdir -p "$mount_point"
        mount "$partition" "$mount_point"
        echo "Mounted $partition to $mount_point"
    else
        echo "Warning: $mount_point is already mounted"
    fi
}

################################################################################
# Preparation
################################################################################

print_banner() {
    echo -e "${B}
                      ##
                     ####
                    ######
                   ########
                  ##########
                 ############                      ${W}░█▀█░█▀▄░█▀▀░█░█░${B}
                ##############                     ${W}░█▀█░█▀▄░█░░░█▀█░${B}
               ################                    ${W}░▀░▀░▀░▀░▀▀▀░▀░▀░${B}
              ##################          ${W}░▀█▀░█▀█░█▀▀░▀█▀░█▀█░█░░░█░░░█▀▀░█▀▄░${B}
             ####################         ${W}░░█░░█░█░▀▀█░░█░░█▀█░█░░░█░░░█▀▀░█▀▄░${B}
            ######################        ${W}░▀▀▀░▀░▀░▀▀▀░░▀░░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░${B}
           #########      #########
          ##########      ##########
         ###########      ###########
        ##########          ##########
       ####                        ####
      ###                            ### ${W}"
}

print_banner

# System setup
loadkeys "${keymap}"
timedatectl set-ntp true

pacman -Sy --needed --noconfirm fzf

# Disk selection
system_disk=$(select_disk)
if ! validate_disk "$system_disk"; then
    echo "Installation aborted: Invalid disk selected"
    exit 1
fi

# Partition selection
system_partition=""
efi_partition=""
swap_partition=""
home_partition=""

select_partition "$system_disk" "system" system_partition

if ! confirm_action "Partition ${Y}${system_partition}${W} will be ${R}ERASED${W}! Are you sure you want to proceed?" "n"; then
    echo "Installation aborted!"
    exit 0
fi

# Format system partition
echo -e "\n[${B}INFO${W}] Formatting ${Y}${system_partition}${W}"
if ! mkfs.ext4 -L Arch -F "${system_partition}"; then
    echo "Error: Failed to format system partition"
    exit 1
fi

select_partition "$system_disk" "EFI" efi_partition
select_partition "$system_disk" "home" home_partition

if confirm_action "Create swap?" "n"; then
    select_partition "$system_disk" "swap" swap_partition
    echo -e "\n[${B}INFO${W}] Activating swap partition"
    swapon "${swap_partition}"
fi

# Mount partitions
echo -e "\n[${B}INFO${W}] Mounting partitions"
mount_with_check "${system_partition}" "/mnt"
mount_with_check "${efi_partition}" "/mnt/boot"
mount_with_check "${home_partition}" "/mnt/home"

# Install base system
echo -e "\n[${B}INFO${W}] Installing Arch Linux base system"
if ! pacstrap /mnt base linux linux-firmware linux-headers; then
    echo "Error: Failed to install base system"
    exit 1
fi

# Generate fstab
echo -e "\n[${B}INFO${W}] Generating fstab"
if ! genfstab -U /mnt >> /mnt/etc/fstab; then
    echo "Error: Failed to generate fstab"
    exit 1
fi

# Copy post-install files
echo -e "[${B}INFO${W}] Copying installation files for post-install"
mkdir -p /mnt/opt/archinstaller
cp -rv config/* /mnt/opt/archinstaller/
cp -v postinstall.sh /mnt/opt/archinstaller/

echo -e "\n[${B}INFO${W}] Installation complete!"
echo -e "[${B}INFO${W}] Running post-install inside chroot..."

if arch-chroot /mnt /bin/bash -c "cd /opt/archinstaller && /bin/bash postinstall.sh && rm -rf /opt/archinstaller"; then
    echo -e "\n[${B}SUCCESS${W}] Installation completed successfully!"
else
    echo -e "\n[${R}ERROR${W}] Post-installation script failed"
    exit 1
fi
