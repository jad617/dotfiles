#!/usr/bin/env bash
# =============================================================================
# Install NixOS onto a second disk from a running Linux (e.g. Pop!_OS), for a
# dual boot without a live USB. The running system is not modified, apart
# from Nix being installed if it's missing (/nix + the nix-daemon service).
#
#   nixos/install-from-linux.sh [--host NAME] [--user NAME] DISK
#     DISK     the whole disk to WIPE, e.g. /dev/nvme1n1 (asks to confirm)
#     --host   flake host (default: this machine's hostname if hosts/<it>.nix exists)
#     --user   NixOS user (default: you)
#
# Then reboot, pick "Linux Boot Manager" on that disk in the firmware boot
# menu (F8 / F11 / F12), log in and run: bash ~/nodestack/dotfiles/nixos/init.sh
# =============================================================================
set -euo pipefail

NIXOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$(dirname "$NIXOS_DIR")"
MNT=/mnt/nixos-install
NIX=(nix --extra-experimental-features "nix-command flakes")

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

HOST="" USERNAME=$(id -un) DISK=""
while (($#)); do
    case $1 in
    --host) HOST=$2 && shift 2 ;;
    --user) USERNAME=$2 && shift 2 ;;
    -h | --help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//' && exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) DISK=$1 && shift ;;
    esac
done

[[ $EUID -ne 0 ]] || die "run as your user (it uses sudo where needed)"
[[ -d /sys/firmware/efi ]] || die "this machine booted without UEFI; only UEFI installs are supported"
[[ -n $DISK ]] || die "which disk? e.g. $0 /dev/nvme1n1 (see: lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS)"

# --- host ---------------------------------------------------------------------
if [[ -z $HOST ]]; then
    [[ -f "$NIXOS_DIR/hosts/$(hostname).nix" ]] || die "no hosts/$(hostname).nix: pass --host (one of: $(cd "$NIXOS_DIR/hosts" && ls | sed 's/\.nix$//' | tr '\n' ' '))"
    HOST=$(hostname)
fi
host_system=$(sed -n "s/^ *$HOST *= *mkHost \"\([^\"]*\)\".*/\1/p" "$NIXOS_DIR/flake.nix")
[[ -n $host_system ]] || die "host '$HOST' is not in nixos/flake.nix"
[[ $host_system == "$(uname -m)-linux" ]] || die "host '$HOST' is $host_system, this machine is $(uname -m)"

# --- the disk: a whole disk with nothing in use on it ----------------------------
[[ -b $DISK ]] || die "$DISK is not a block device"
disk_type=$(lsblk -dno TYPE "$DISK")
[[ $disk_type == disk || ($disk_type == loop && -n ${NIXOS_INSTALL_ALLOW_LOOP:-}) ]] ||
    die "$DISK is a $disk_type, not a whole disk"
# Covers the running system: its partitions, LUKS / LVM volumes and swap all
# show up as mountpoints in the disk's tree
if lsblk -nro MOUNTPOINTS "$DISK" | grep -q .; then
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$DISK" >&2
    die "$DISK is in use (mounted partitions or swap): pick the empty disk"
fi
part() { if [[ $DISK =~ [0-9]$ ]]; then echo "${DISK}p$1"; else echo "${DISK}$1"; fi; }

# --- password, timezone ---------------------------------------------------------
PASSWORD=${NIXOS_PASSWORD:-}
if [[ -z $PASSWORD ]]; then
    read -rsp "Password for $USERNAME on NixOS: " PASSWORD && echo
    read -rsp "Again: " again && echo
    [[ $PASSWORD == "$again" && -n $PASSWORD ]] || die "passwords are empty or do not match"
fi
TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || true)
TIMEZONE=${TIMEZONE:-America/Toronto}

# --- confirm --------------------------------------------------------------------
echo
lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DISK"
echo
echo "NixOS host '$HOST' ($host_system), user $USERNAME, timezone $TIMEZONE"
echo "EVERYTHING on $DISK will be erased."
if [[ -z ${NIXOS_INSTALL_YES:-} ]]; then
    read -rp "Type $(basename "$DISK") to continue: " answer
    [[ $answer == "$(basename "$DISK")" ]] || die "cancelled"
fi

# --- Nix (only if missing) --------------------------------------------------------
if ! command -v nix >/dev/null; then
    info "Installing Nix (multi-user: /nix + nix-daemon)"
    sh <(curl -fsSL https://nixos.org/nix/install) --daemon --yes
    # shellcheck source=/dev/null
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Install tools from the nixpkgs revision pinned in flake.lock
# (the root's nixpkgs input, e.g. node "nixpkgs_2", not the first "nixpkgs" node)
rev=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["nodes"]; print(d[d["root"]["inputs"]["nixpkgs"]]["locked"]["rev"])' \
    "$NIXOS_DIR/flake.lock" 2>/dev/null || true)
[[ -n $rev ]] || die "no nixpkgs revision in nixos/flake.lock"
info "Fetching nixos-install and disk tools (nixpkgs ${rev:0:7})"
tools=$("${NIX[@]}" build --no-link --print-out-paths \
    "github:nixos/nixpkgs/$rev#nixos-install-tools" "github:nixos/nixpkgs/$rev#parted" \
    "github:nixos/nixpkgs/$rev#dosfstools" "github:nixos/nixpkgs/$rev#e2fsprogs")
TOOL_PATH=""
for t in $tools; do
    if [[ -d $t/bin ]]; then TOOL_PATH+="$t/bin:"; fi
    if [[ -d $t/sbin ]]; then TOOL_PATH+="$t/sbin:"; fi
done
TOOL_PATH+="$(dirname "$(command -v nix)"):$PATH"
as_root() { sudo env "PATH=$TOOL_PATH" "$@"; }

# --- partition + format -------------------------------------------------------------
info "Partitioning $DISK: 1 GiB EFI + NixOS"
as_root parted -s "$DISK" -- mklabel gpt \
    mkpart ESP fat32 1MiB 1GiB set 1 esp on \
    mkpart nixos ext4 1GiB 100%
as_root partprobe "$DISK" 2>/dev/null || true
sudo udevadm settle
as_root mkfs.fat -F 32 -n NIXBOOT "$(part 1)" >/dev/null
as_root mkfs.ext4 -qF -L nixos "$(part 2)"
sudo mkdir -p "$MNT"
sudo mount "$(part 2)" "$MNT"
sudo mkdir -p "$MNT/boot"
sudo mount -o umask=077 "$(part 1)" "$MNT/boot"
trap 'sudo umount -R "$MNT" 2>/dev/null || true' EXIT

# --- config + install ---------------------------------------------------------------
info "Writing $MNT/etc/nixos"
as_root bash "$NIXOS_DIR/write-config.sh" "$MNT" "$USERNAME" "$TIMEZONE"
# nixos-generate-config lists every active swap, including this system's
# (Pop!_OS: encrypted cryptswap), which NixOS would then wait for at boot
as_root python3 -I -c 'import re,sys; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(re.sub(r"swapDevices\s*=\s*\[.*?\];", "swapDevices = [ ];", s, flags=re.S))' \
    "$MNT/etc/nixos/hardware-configuration.nix"

info "nixos-install (first build takes a while)"
extra=()
[[ -n ${NIXOS_INSTALL_NO_BOOTLOADER:-} ]] && extra+=(--no-bootloader) # tests only
as_root nixos-install --root "$MNT" --flake "$MNT/etc/nixos#$HOST" --impure \
    --no-root-passwd --no-channel-copy --option experimental-features "nix-command flakes" \
    ${extra[@]+"${extra[@]}"}

info "User $USERNAME, and this checkout in ~/nodestack/dotfiles"
echo "$USERNAME:$PASSWORD" | as_root nixos-enter --root "$MNT" -c chpasswd
uid_gid=$(as_root nixos-enter --root "$MNT" -c "id -u $USERNAME; id -g $USERNAME" 2>/dev/null | tr '\n' ':' | sed 's/:$//')
sudo mkdir -p "$MNT/home/$USERNAME/nodestack"
sudo rm -rf "$MNT/home/$USERNAME/nodestack/dotfiles"
sudo cp -a "$DOTFILES" "$MNT/home/$USERNAME/nodestack/dotfiles"
sudo chown -R "$uid_gid" "$MNT/home/$USERNAME/nodestack"

sudo umount -R "$MNT"
trap - EXIT
echo
info "Done. Reboot, open the firmware boot menu (F8 / F11 / F12) and pick"
model=$(lsblk -dno MODEL "$DISK" 2>/dev/null | sed 's/ *$//' || true)
echo "    \"Linux Boot Manager\" on ${model:-$DISK} ($DISK)."
echo "    Log in as $USERNAME, then run: bash ~/nodestack/dotfiles/nixos/init.sh"
echo "    Pop!_OS stays on its own disk; set the default OS in the firmware settings."
