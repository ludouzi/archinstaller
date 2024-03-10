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
# Post-install
################################################################################

# Install the latest archlinux-keyring
echo -e "[${B}INFO${W}] Install the latest ${Y}archlinux-keyring${W} package"
pacman -Sy --needed archlinux-keyring

# Configure pacman.conf
echo -e "[${B}INFO${W}] Modifying pacman configuration"
sed -i 's #Color Color ; s #\[multilib\] \[multilib\] ; /\[multilib\]/{n;s #Include Include }' /etc/pacman.conf
pacman -Syu --noconfirm

# Install all packages
echo -e "[${B}INFO${W}] Install ${Y}pacman${W} packages"
pacman -Sy --needed - < /opt/config-pacman-packages.txt

# Configuration
echo -e "[${B}INFO${W}] Configure system localization"
ln -sf /usr/share/zoneinfo/"${timezone}" /etc/localtime
hwclock --systohc
sed -i "s|^#${locale}.UTF-8|${locale}.UTF-8|" /etc/locale.gen
locale-gen
echo "LANG=${locale}.UTF-8" > /etc/locale.conf
echo "KEYMAP=${keymap}" > /etc/vconsole.conf
echo "${hostname}" > /etc/hostname

# Create user (if not already exists)
if id -u "${username}" >/dev/null 2>&1; then
    echo -e "[${B}INFO${W}] User already exists"
else
    echo -e "[${B}INFO${W}] Generate user & password"
    useradd -m -G wheel -s "${shell}" "${username}"
    echo -e "Defaults passwd_timeout=0\n%wheel ALL=(ALL:ALL) ALL\n" > /etc/sudoers.d/wheel
    chown -c root:root /etc/sudoers.d/wheel
    chmod -c 0400 /etc/sudoers.d/wheel
fi 

# Change password for root & ${username}
echo -e "Change password for user ${Y}root${W} :"
passwd root
echo -e "Change password for user ${Y}${username}${W} :"
passwd "${username}"

# Install paru
echo -e "[${B}INFO${W}] Install ${Y}paru${W}"
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
chown -R ${username}: .
sudo -u ${username} makepkg -si
cd
rm -rf /tmp/paru
paru --version

# Configure paru.conf
echo -e "[${B}INFO${W}] Modifying paru configuration"
sed -i 's #RemoveMake RemoveMake ; s #CleanAfter CleanAfter ;' /etc/paru.conf
paru -Syu --noconfirm

# Install AUR Packages
echo -e "[${B}INFO${W}] Install ${Y}AUR${W} packages"
sudo -u ${username} paru -Sy --needed - < /opt/config-aur-packages.txt

# Start services
echo -e "[${B}INFO${W}] Enable systemctl services"
systemctl enable intel-undervolt
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable tlp

# Reboot
echo -e "[${B}INFO${W}] Post-install complete!"
echo -e "[${B}INFO${W}] Type ${Y}CTRL+D${W} and ${Y}reboot${W} to reboot to Arch."
