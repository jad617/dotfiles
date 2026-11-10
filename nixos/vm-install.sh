#!/usr/bin/env bash
# =============================================================================
# Runs inside the NixOS installer ISO, started by nixos/vm.sh over the VM's
# serial console. Wipes /dev/vda, installs the nixos-arm flake host from the
# dotfiles tarball served by vm.sh, sets the user's password + SSH key, powers off.
#
#   VM_USER, VM_PASSWORD, VM_TIMEZONE, VM_SSH_KEY   (passed by vm.sh)
# =============================================================================
set -euo pipefail

USERNAME=${VM_USER:?VM_USER is not set}
PASSWORD=${VM_PASSWORD:?VM_PASSWORD is not set}
TIMEZONE=${VM_TIMEZONE:-America/Toronto}
NIXOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK=/dev/vda

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }
[[ -b $DISK ]] || { echo "$DISK not found"; exit 1; }

echo "==> Partitioning $DISK"
umount -R /mnt 2>/dev/null || true
parted -s "$DISK" -- mklabel gpt \
    mkpart ESP fat32 1MB 512MB set 1 esp on \
    mkpart root ext4 512MB 100%
udevadm settle
mkfs.fat -F 32 -n boot "${DISK}1"
mkfs.ext4 -qF -L nixos "${DISK}2"
udevadm settle
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot

echo "==> Writing /mnt/etc/nixos"
bash "$NIXOS_DIR/write-config.sh" /mnt "$USERNAME" "$TIMEZONE"

echo "==> nixos-install (first build takes a while)"
nixos-install --flake /mnt/etc/nixos#nixos-arm --impure --no-root-passwd --no-channel-copy \
    --option experimental-features "nix-command flakes"

echo "==> User $USERNAME"
echo "$USERNAME:$PASSWORD" | nixos-enter --root /mnt -c chpasswd
if [[ -n "${VM_SSH_KEY:-}" ]]; then
    install -d -m 700 -o 1000 -g 100 "/mnt/home/$USERNAME/.ssh"
    echo "$VM_SSH_KEY" >"/mnt/home/$USERNAME/.ssh/authorized_keys"
    chown 1000:100 "/mnt/home/$USERNAME/.ssh/authorized_keys"
    chmod 600 "/mnt/home/$USERNAME/.ssh/authorized_keys"
fi

echo "==> VM-INSTALL-DONE"
umount -R /mnt
poweroff
