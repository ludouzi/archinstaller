#!/bin/bash
################################################################################
#
# Author  : Luke Taylor
# GitHub  : https://github.com/ludouzi/archinstaller
#
################################################################################

set -e

################################################################################
# Source variables
################################################################################

. config-variables.sh

################################################################################
# Preparation
################################################################################
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

loadkeys ${keymap}
timedatectl set-ntp true

# Disk partition
echo -e "[${B}INFO${W}] Select install disk"
echo "Disk(s) available:"
parted -l | awk '/Disk \//{ gsub(":","") ; print "- \033[93m"$2"\033[0m",$3}' | column -t
read -r -p "Please enter a disk: " system_disk

echo -e "\n[${B}INFO${W}] Select install partition"
echo "Partition(s) available:"
parted ${system_disk} print | awk '$1+0' | column -t
read -r -p "Please enter a partition: " system_partition
system_partition="${system_disk}${system_partition}"

echo -e "\nPartition ${Y}${system_partition}${W} will be ${R}ERASED${W} !"
read -r -p "Are you sure you want to proceed? (y/n)" system_partition_format

if [[ "${system_partition_format}" != "y" ]] ; then
    echo "Installation aborted!"
    exit 0
fi

# Format partition
echo -e "\n[${B}INFO${W}] Format ${Y}${system_partition}${W}"
mkfs.ext4 -L Arch "${system_partition}"

echo -e "\n[${B}INFO${W}] Select EFI partition"
echo "Partition(s) available:"
parted ${system_disk} print | awk '$1+0' | column -t
read -r -p "Please enter a partition: " efi_partition
efi_partition="${system_disk}${efi_partition}"

echo -e "\n[${B}INFO${W}] Select home partition"
echo "Partition(s) available:"
parted ${system_disk} print | awk '$1+0' | column -t
read -r -p "Please enter a partition: " home_partition
home_partition="${system_disk}${home_partition}"

read -r -p "Create swap? (y/n)" create_swap
if [[ $create_swap = y ]] ; then
	echo -e "\n[${B}INFO${W}] Select swap partition"
	echo "Partition(s) available:"
	parted ${system_disk} print | awk '$1+0' | column -t
	read -r -p "Please enter a partition: " swap_partition
	swap_partition="${system_disk}${swap_partition}"
	
	# Mount swap
	swapon ${swap_partition}
fi

# Mount root
echo -e "\n[${B}INFO${W}] Mount Root Partition"
mount "${system_partition}" /mnt

# Mount EFI
echo -e "[${B}INFO${W}] Mount EFI Partition"
mkdir /mnt/boot
mount "${efi_partition}" /mnt/boot

# Mount home
echo -e "[${B}INFO${W}] Mount Home Partition"
mkdir /mnt/home
mount "${home_partition}" /mnt/home

# Install Arch
echo -e "\n[${B}INFO${W}] Install Arch Linux"
pacstrap /mnt base linux linux-firmware linux-headers

# Generate fstab
echo -e "\n[${B}INFO${W}] Generate fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# Copy postinstall files to /mnt chroot
echo -e "[${B}INFO${W}] Copy installation for post-install"
cp -v postinstall.sh /mnt/opt
cp -v config-variables.sh /mnt/opt
cp -v config-pacman-packages.txt /mnt/opt
cp -v config-aur-packages.txt /mnt/opt

echo -e "\n[${B}INFO${W}] Installation complete!"
echo -e "[${B}INFO${W}] Run ${Y}arch-chroot /mnt${W}, ${Y}cd /opt${W} and ${Y}./postinstall.sh${W} to continue"
