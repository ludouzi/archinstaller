#!/bin/bash

set -euo pipefail

source /opt/archinstaller/variables.sh

################################################################################
# Functions
################################################################################

run_with_status() {
    local message="$1"
    shift
    echo -e "[${B}INFO${W}] $message"
    if "$@"; then
        echo -e "[${G}OK${W}] $message completed"
    else
        echo -e "[${R}ERROR${W}] $message failed"
        return 1
    fi
}

configure_pacman() {   
    if [[ ! -f /opt/archinstaller/pacman.conf ]]; then
        echo -e "[${R}ERROR${W}] Custom pacman.conf not found at /opt/archinstaller/pacman.conf"
        return 1
    fi
    
    cp /opt/archinstaller/pacman.conf /etc/pacman.conf
    chmod 644 /etc/pacman.conf
    echo -e "[${G}OK${W}] Custom pacman.conf applied successfully"
}

install_pacman_packages() {
    if [[ ! -f /opt/archinstaller/pacman-packages.txt ]]; then
        echo "Error: Package list not found at /opt/archinstaller/pacman-packages.txt"
        return 1
    fi
    
    # Check if all packages exist before installing
    if ! pacman -Sp --print-format '%n' $(grep -v '^#' /opt/archinstaller/pacman-packages.txt) > /dev/null 2>&1; then
        echo "Warning: Some packages in the list may not be available"
    fi
    
    pacman -Sy --needed --noconfirm - < /opt/archinstaller/pacman-packages.txt
}

install_aur_packages() {
    if [[ ! -f /opt/archinstaller/aur-packages.txt ]]; then
        echo "Error: AUR package list not found at /opt/archinstaller/aur-packages.txt"
        return 1
    fi
    
    sudo -u "${username}" paru -Sy --needed --noconfirm - < /opt/archinstaller/aur-packages.txt
}

create_user() {
    local username="$1"
    local shell="$2"
    
    if id -u "${username}" >/dev/null 2>&1; then
        echo -e "[${B}INFO${W}] User $username already exists"
        return 0
    fi
    
    echo -e "[${B}INFO${W}] Creating user $username"
    useradd -m -G wheel -s "${shell}" "${username}"
    
    echo "Defaults passwd_timeout=0" > /etc/sudoers.d/wheel
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/wheel
    chown root:root /etc/sudoers.d/wheel
    chmod 0400 /etc/sudoers.d/wheel
}

change_password() {
    local username="$1"
    echo -e "Change password for user ${Y}${username}${W}:"
    until passwd "${username}"; do
        echo "Password change failed for $username, please try again"
    done
}

install_paru() {
    local username="$1"

    if command -v paru >/dev/null 2>&1; then
        echo -e "[${B}INFO${W}] paru is already installed"
        return 0
    fi
    
    cd /tmp
    git clone https://aur.archlinux.org/paru.git
    cd paru
    chown -R ${username}:.
    sudo -u ${username} makepkg -si --noconfirm
    cd
    rm -rf /tmp/paru
    
    if command -v paru >/dev/null 2>&1; then
        echo -e "[${G}OK${W}] paru installed successfully"
        paru --version
    else
        echo -e "[${R}ERROR${W}] paru installation failed"
        return 1
    fi
}

configure_kde() {   
    # Configure applications menu (for dolphin)
    mkdir /etc/xdg/menus
    curl -L --fail \
        https://raw.githubusercontent.com/KDE/plasma-workspace/master/menu/desktop/plasma-applications.menu \
        -o /etc/xdg/menus/applications.menu
    
    if command -v balooctl6 >/dev/null 2>&1; then
        balooctl6 suspend
        balooctl6 disable
        balooctl6 purge
    fi
}

configure_libvirt() {   
    local username="$1"
    usermod -aG libvirt "$username"
}

################################################################################
# Main Post-install
################################################################################

main() {
    echo -e "\n[${B}INFO${W}] Starting post-installation setup\n"

    run_with_status "Installing latest archlinux-keyring" \
        pacman -Sy --needed --noconfirm archlinux-keyring

    run_with_status "Configuring pacman with custom configuration" \
        configure_pacman

    run_with_status "Performing system update" \
        pacman -Syu --noconfirm

    run_with_status "Installing pacman packages" \
        install_pacman_packages

    echo -e "[${B}INFO${W}] Configuring system localization"
    
    ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
    hwclock --systohc
    
    for locale in $locales; do
        sed -i "s|^#${locale}|${locale}|" /etc/locale.gen
    done
    locale-gen
    
    echo "LANG=${locale}.UTF-8" > /etc/locale.conf
    echo "KEYMAP=${keymap}" > /etc/vconsole.conf
    echo "${hostname}" > /etc/hostname

    run_with_status "Creating user ${username}" \
        create_user "${username}" "${shell}"

    change_password "root"
    change_password "${username}"

    run_with_status "Installing paru AUR helper" \
        install_paru "${username}"

    # Configure paru
    if command -v paru >/dev/null 2>&1; then
        run_with_status "Configuring paru" \
            sed -i /etc/paru.conf \
                -e 's/#RemoveMake/RemoveMake/' \
                -e 's/#CleanAfter/CleanAfter/'
        
        run_with_status "Updating system with paru" \
            paru -Syu --noconfirm
        
        run_with_status "Installing AUR packages" \
            install_aur_packages
    fi

    run_with_status "Configuring KDE apps" \
        configure_kde

    # Enable services
    echo -e "[${B}INFO${W}] Enabling system services"
    systemctl enable libvirtd
    systemctl enable NetworkManager
    systemctl enable sddm
    systemctl enable sshd

    run_with_status "Configuring libvirt" \
        configure_libvirt "${username}"

    echo -e "\n[${G}SUCCESS${W}] Post-installation completed successfully!"
    echo -e "[${B}INFO${W}] Type ${Y}CTRL+D${W} and ${Y}reboot${W} to reboot to Arch."
    echo -e "[${B}INFO${W}] Don't forget to remove the installation media!\n"
}

main "$@"