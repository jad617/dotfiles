#!/usr/bin/env bash
# =============================================================================
# Install NixOS onto a disk, either from a running Linux (e.g. Pop!_OS) for a
# dual boot without a live USB, or from a live CD / USB (NixOS ISO, Ubuntu...).
# The running system is not modified, apart from Nix being installed if it's
# missing (/nix + the nix-daemon service). The running system's disk is never
# offered; a disk holding another OS is only offered for a full erase, behind
# a warning that lists what is destroyed.
#
#   nixos/install-from-linux.sh                 guided, arrow-key menus: host, disk, layout, user, password
#   nixos/install-from-linux.sh [options] DISK                   erase DISK: EFI + NixOS
#   nixos/install-from-linux.sh [options] --free-space DISK      EFI + NixOS in DISK's free space
#   nixos/install-from-linux.sh [options] --shrink PART --keep N shrink ext4 PART to N GiB, use the rest
#   nixos/install-from-linux.sh [options] --boot-part P --root-part P   format these two only
#     --size N     NixOS partition size in GiB (--free-space / --shrink; default: all the space)
#     --wifi W     Wi-Fi networks saved here to copy to NixOS: active (default), all, none,
#                  or names separated by commas (the guided mode asks)
#     --ssh S      SSH keys / files from ~/.ssh to copy to NixOS: none (default), all, or
#                  names separated by commas, e.g. id_rsa,known_hosts (the guided mode asks)
#     --host       flake host (default: this machine's hostname if hosts/<it>.nix exists;
#                  required on a live CD)
#     --user       NixOS user (default: you; required on a live CD)
#     --timezone   e.g. Europe/Paris (default: this system's, America/Toronto on a live CD)
#   NIXOS_PASSWORD=...                   skip the password prompt
#   NIXOS_INSTALL_YES=1                  skip the typed confirmation
#   NIXOS_INSTALL_ALLOW_OS_DISK=/dev/X   let DISK mode erase X although it holds another OS
#   NIXOS_INSTALL_TEXT=1                 numbered prompts instead of the arrow-key menus
#
# Then reboot, pick "Linux Boot Manager" on that disk in the firmware boot
# menu (F8 / F11 / F12), log in and run: bash ~/nodestack/dotfiles/nixos/init.sh
# See nixos/INSTALL.md.
# =============================================================================
set -euo pipefail

NIXOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$(dirname "$NIXOS_DIR")"
MNT=${NIXOS_INSTALL_MNT:-/mnt/nixos-install}
NIX=(nix --extra-experimental-features "nix-command flakes")
EFI_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
GiB=1073741824
MIN_NIXOS_GIB=20

# --- output -------------------------------------------------------------------------
if [[ -t 1 ]]; then
    B=$'\033[1m' DIM=$'\033[2m' BLUE=$'\033[1;34m' RED=$'\033[1;31m' YELLOW=$'\033[1;33m' R=$'\033[0m'
else
    B="" DIM="" BLUE="" RED="" YELLOW="" R=""
fi
STEP=0 STEPS=7
info() { printf '%s==>%s %s\n' "$BLUE" "$R" "$*"; }
step() {
    STEP=$((STEP + 1))
    printf '\n%s[%d/%d]%s %s%s%s\n' "$BLUE" "$STEP" "$STEPS" "$R" "$B" "$*" "$R"
}
warn() { printf '%swarning:%s %s\n' "$YELLOW" "$R" "$*" >&2; }
die() {
    printf '%serror:%s %s\n' "$RED" "$R" "$*" >&2
    exit 1
}
# box "title" "line" ...   (same frame as init.sh's closing box, sized to the text)
box() {
    local title=$1 l w=0 bar
    shift
    for l in "$title" "$@"; do ((${#l} > w)) && w=${#l}; done
    bar=$(printf '─%.0s' $(seq 1 $((w + 4))))
    printf '┌%s┐\n' "$bar"
    printf '│  %s%-*s%s  │\n' "$B" "$w" "$title" "$R"
    printf '│  %-*s  │\n' "$w" ""
    for l in "$@"; do printf '│  %-*s  │\n' "$w" "$l"; done
    printf '└%s┘\n' "$bar"
}
# Live CDs often give a root shell, and some have no sudo
sudo() { if ((EUID == 0)); then "$@"; else command sudo "$@"; fi; }
gib() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1073741824 }'; } # bytes -> "12.3"

# --- UI: a small full-screen TUI of its own (arrow keys + Enter), plain prompts without a terminal -
# Every screen shows a header with what was chosen so far (CRUMBS). Keys: Up/Down or k/j to move,
# Enter to pick, q or Esc to quit. Nothing is changed on any disk before the final typed confirmation.
UI=text
[[ -t 0 && -t 1 && -z ${NIXOS_INSTALL_TEXT:-} ]] && UI=tui
TITLE="NixOS install"
CRUMBS=()
REV=$'\033[7m' CLR=$'\033[H\033[2J'
ui_restore() { [[ $UI == tui ]] && printf '\033[?25h' >/dev/tty; return 0; }
trap ui_restore EXIT
screen() { # HEADING TEXT: clear, title bar, breadcrumbs, heading, text
    local cols bar crumb=""
    cols=$(tput cols 2>/dev/null || echo 80)
    ((${#CRUMBS[@]})) && crumb=$(printf '%s  >  ' "${CRUMBS[@]}") && crumb=${crumb%  >  }
    bar=" $TITLE${crumb:+   |   $crumb}"
    printf '%s%s%-*s%s\n\n' "$CLR" "$REV$B" "$cols" "${bar:0:cols}" "$R"
    if [[ $1 == WARNING* ]]; then printf '  %s%s%s\n' "$RED" "$1" "$R"; else printf '  %s%s%s\n' "$B" "$1" "$R"; fi
    [[ -n $2 ]] && printf '\n%s\n' "$2" | sed 's/^/  /'
    echo
}
# ui_menu "heading" "text" tag item [tag item...]  -> REPLY (the tag of the picked item)
ui_menu() {
    local head=$1 text=$2 tags=() items=() i sel=0 key rest
    shift 2
    (($#)) || die "nothing to choose from: $head"
    while (($#)); do tags+=("$1") items+=("$2") && shift 2; done
    if [[ $UI == text ]]; then
        printf '\n%s%s%s\n' "$B" "$head" "$R"
        [[ -n $text ]] && printf '%s\n' "$text"
        for i in "${!items[@]}"; do printf '  %s%2d)%s %s\n' "$BLUE" "$((i + 1))" "$R" "${items[$i]}"; done
        while true; do
            read -rp "  number [1-${#items[@]}]: " key </dev/tty || die "cancelled"
            [[ $key =~ ^[0-9]+$ ]] && ((key >= 1 && key <= ${#items[@]})) && break
        done
        REPLY=${tags[$((key - 1))]}
        return
    fi
    printf '\033[?25l' >/dev/tty
    while true; do
        {
            screen "$head" "$text"
            for i in "${!items[@]}"; do
                if ((i == sel)); then printf '  %s%s > %s %s\n' "$REV" "$B" "${items[$i]}" "$R"; else printf '    %s\n' "${items[$i]}"; fi
            done
            printf '\n  %s↑/↓ move   Enter select   q quit%s\n' "$DIM" "$R"
        } >/dev/tty
        IFS= read -rsn1 key </dev/tty || die "cancelled"
        if [[ $key == $'\033' ]]; then
            IFS= read -rsn2 -t 0.05 rest </dev/tty || rest=""
            case $rest in
            '[A') key=up ;; '[B') key=down ;; '[H') key=home ;; '[F') key=end ;; '') key=quit ;; *) key="" ;;
            esac
        fi
        case $key in
        up | k) ((sel > 0)) && sel=$((sel - 1)) ;;
        down | j) ((sel < ${#items[@]} - 1)) && sel=$((sel + 1)) ;;
        home | g) sel=0 ;;
        end | G) sel=$((${#items[@]} - 1)) ;;
        [1-9]) ((key <= ${#items[@]})) && sel=$((key - 1)) ;;
        '') break ;; # Enter
        q | quit) printf '\033[?25h' >/dev/tty && die "cancelled" ;;
        esac
    done
    printf '\033[?25h' >/dev/tty
    REPLY=${tags[$sel]}
}
# ui_input "heading" "text" [default]  -> REPLY (the default is pre-filled and editable)
ui_input() {
    if [[ $UI == tui ]]; then
        screen "$1" "$2" >/dev/tty
        read -rep "  > " -i "${3:-}" REPLY </dev/tty || die "cancelled"
    else
        printf '\n%s%s%s\n%s\n' "$B" "$1" "$R" "$2"
        read -rp "  ${3:+[$3] }> " REPLY </dev/tty || die "cancelled"
        REPLY=${REPLY:-${3:-}}
    fi
}
ui_password() { # "heading" "text" -> REPLY
    [[ $UI == tui ]] && screen "$1" "" >/dev/tty
    read -rsp "  $2 " REPLY </dev/tty || die "cancelled"
    echo
}
# ui_yesno "heading" "text" [yes-label no-label]  -> status 0 for yes; the default is no
ui_yesno() {
    local REPLY
    ui_menu "$1" "$2" no "${4:-No}" yes "${3:-Yes}"
    [[ $REPLY == yes ]]
}
ui_msg() {
    if [[ $UI == tui ]]; then
        screen "$1" "$2" >/dev/tty
        read -rsn1 -p "  press a key" </dev/tty || true
    else
        printf '\n%s%s%s\n%s\n' "$B" "$1" "$R" "$2"
    fi
}

# ui_checklist "heading" "text" tag item on|off [...]  -> REPLY: the ticked tags, space-separated
# (tags must not contain spaces). Space ticks, a ticks all / none, Enter accepts.
ui_checklist() {
    local head=$1 text=$2 tags=() items=() on=() i sel=0 key rest n
    shift 2
    while (($#)); do tags+=("$1") items+=("$2") on+=("$3") && shift 3; done
    if [[ $UI == text ]]; then
        while true; do
            printf '\n%s%s%s\n' "$B" "$head" "$R"
            [[ -n $text ]] && printf '%s\n' "$text"
            for i in "${!items[@]}"; do printf '  %s%2d)%s [%s] %s\n' "$BLUE" "$((i + 1))" "$R" "$([[ ${on[$i]} == on ]] && echo x || echo ' ')" "${items[$i]}"; done
            read -rp "  numbers to tick / untick (e.g. 1,3), 'all', 'none', Enter when done: " key </dev/tty || die "cancelled"
            [[ -z $key ]] && break
            case $key in
            all) for i in "${!on[@]}"; do on[$i]=on; done ;;
            none) for i in "${!on[@]}"; do on[$i]=off; done ;;
            *) for n in ${key//,/ }; do
                [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#items[@]})) || continue
                if [[ ${on[$((n - 1))]} == on ]]; then on[$((n - 1))]=off; else on[$((n - 1))]=on; fi
            done ;;
            esac
        done
    else
        printf '\033[?25l' >/dev/tty
        while true; do
            {
                screen "$head" "$text"
                for i in "${!items[@]}"; do
                    local box="[ ]"
                    [[ ${on[$i]} == on ]] && box="[x]"
                    if ((i == sel)); then printf '  %s%s > %s %s %s\n' "$REV" "$B" "$box" "${items[$i]}" "$R"; else printf '    %s %s\n' "$box" "${items[$i]}"; fi
                done
                printf '\n  %s↑/↓ move   Space tick   a all/none   Enter accept   q quit%s\n' "$DIM" "$R"
            } >/dev/tty
            IFS= read -rsn1 key </dev/tty || die "cancelled"
            if [[ $key == $'\033' ]]; then
                IFS= read -rsn2 -t 0.05 rest </dev/tty || rest=""
                case $rest in '[A') key=up ;; '[B') key=down ;; '') key=quit ;; *) key="" ;; esac
            fi
            case $key in
            up | k) ((sel > 0)) && sel=$((sel - 1)) ;;
            down | j) ((sel < ${#items[@]} - 1)) && sel=$((sel + 1)) ;;
            ' ') if [[ ${on[$sel]} == on ]]; then on[$sel]=off; else on[$sel]=on; fi ;;
            a) if [[ " ${on[*]} " == *" off "* ]]; then for i in "${!on[@]}"; do on[$i]=on; done; else for i in "${!on[@]}"; do on[$i]=off; done; fi ;;
            '') break ;;
            q | quit) printf '\033[?25h' >/dev/tty && die "cancelled" ;;
            esac
        done
        printf '\033[?25h' >/dev/tty
    fi
    REPLY=""
    for i in "${!tags[@]}"; do [[ ${on[$i]} == on ]] && REPLY+="${tags[$i]} "; done
    REPLY=${REPLY% }
    return 0
}

# --- arguments ----------------------------------------------------------------------
HOST="" USERNAME="" TIMEZONE="" DISK="" BOOT_PART="" ROOT_PART=""
FREE_DISK="" SHRINK_PART="" SHRINK_GIB="" NIXOS_GIB="" WIFI_ARG="" SSH_ARG=""
while (($#)); do
    case $1 in
    --host) HOST=$2 && shift 2 ;;
    --user) USERNAME=$2 && shift 2 ;;
    --timezone) TIMEZONE=$2 && shift 2 ;;
    --boot-part) BOOT_PART=$2 && shift 2 ;;
    --root-part) ROOT_PART=$2 && shift 2 ;;
    --free-space) FREE_DISK=$2 && shift 2 ;;
    --shrink) SHRINK_PART=$2 && shift 2 ;;
    --keep) SHRINK_GIB=$2 && shift 2 ;;
    --size) NIXOS_GIB=$2 && shift 2 ;;
    --wifi) WIFI_ARG=$2 && shift 2 ;;
    --ssh) SSH_ARG=$2 && shift 2 ;;
    -h | --help) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//' && exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) DISK=$1 && shift ;;
    esac
done

[[ -d /sys/firmware/efi ]] || die "this machine booted without UEFI; only UEFI installs are supported"
# Another install may be running and using it: mounting over it would break that install
if mountpoint -q "$MNT" || [[ -n $(findmnt -rno TARGET -R "$MNT" 2>/dev/null) ]]; then
    findmnt -R "$MNT" >&2 || true
    die "$MNT is in use (another install running?). Wait for it, or unmount it: sudo umount -R $MNT"
fi
modes=0
[[ -n $DISK ]] && modes=$((modes + 1))
[[ -n $FREE_DISK ]] && modes=$((modes + 1))
[[ -n $SHRINK_PART ]] && modes=$((modes + 1))
[[ -n $BOOT_PART || -n $ROOT_PART ]] && modes=$((modes + 1))
((modes <= 1)) || die "pick one of: DISK, --free-space, --shrink, --boot-part/--root-part"
if [[ -n $BOOT_PART || -n $ROOT_PART ]]; then
    [[ -n $BOOT_PART && -n $ROOT_PART ]] || die "--boot-part and --root-part go together"
fi
[[ -z $SHRINK_PART || $SHRINK_GIB =~ ^[0-9]+$ ]] || die "--shrink needs --keep N (GiB to keep for $SHRINK_PART)"
[[ -z $NIXOS_GIB || $NIXOS_GIB =~ ^[0-9]+$ ]] || die "--size takes a whole number of GiB"
GUIDED=""
if ((modes == 0)); then
    [[ -t 0 ]] || die "which disk? e.g. $0 /dev/nvme1n1, or run it in a terminal to choose (see: lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS)"
    GUIDED=1
fi

# A live CD: / is in RAM, and its hostname ("nixos", "ubuntu") and user mean nothing.
# (The NixOS ISO's hostname "nixos" is also the name of the VM host in flake.nix.)
LIVE=""
if grep -q '^VARIANT_ID=installer' /etc/os-release 2>/dev/null ||
    [[ $(findmnt -no FSTYPE / 2>/dev/null) =~ ^(overlay|tmpfs|squashfs|aufs|rootfs)$ ]] ||
    [[ -d /cdrom/casper || -d /run/initramfs/live || -d /iso ]]; then
    LIVE=1
else
    [[ $EUID -ne 0 ]] || die "run as your user (it uses sudo where needed)"
fi
[[ -n $LIVE && -z $GUIDED ]] && info "Live system detected: the host and user are not guessed"

# --- what is on the disks ---------------------------------------------------------------------
# Disks the running system needs: what / and every active swap sit on, and the live medium
SYS_DISKS=$({
    findmnt -nvo SOURCE /
    swapon --show=NAME --noheadings 2>/dev/null
    for m in /iso /cdrom /run/initramfs/live /run/live/medium /lib/live/mount/medium /run/archiso/bootmnt; do
        findmnt -nvo SOURCE "$m" 2>/dev/null || true
    done
} | grep '^/dev/' | xargs -r -n1 lsblk -nrspo NAME,TYPE 2>/dev/null | awk '$2 == "disk" && $1 !~ /zram/ { print $1 }' | sort -u)

if ! command -v nix >/dev/null && [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck source=/dev/null
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
# Firmware boot entries: which partitions hold another OS's boot loader
BOOT_ENTRIES=""
if command -v efibootmgr >/dev/null; then
    BOOT_ENTRIES=$(efibootmgr -v 2>/dev/null || true)
elif command -v nix >/dev/null; then
    BOOT_ENTRIES=$("${NIX[@]}" shell nixpkgs#efibootmgr -c efibootmgr -v 2>/dev/null || true)
fi
[[ -n $BOOT_ENTRIES ]] ||
    warn "could not read the firmware boot entries (efibootmgr): disks are only checked for LUKS / LVM / Windows partitions"

parts_of() { lsblk -lnpo NAME,TYPE "$1" | awk '$2 == "part" { print $1 }'; }
boot_entry_of() { # PARTITION -> name of the firmware boot entry that points to it, if any
    local u
    u=$(lsblk -dno PARTUUID "$1")
    [[ -n $u && -n $BOOT_ENTRIES ]] || return 0
    grep -i "HD([0-9]*,GPT,$u" <<<"$BOOT_ENTRIES" | head -1 |
        sed 's/^Boot[0-9A-Fa-f]\{4\}\*\{0,1\} *//; s/[[:space:]]*HD(.*//' || true
}
# Another OS on the disk: a partition that a firmware boot entry points to (except NixOS's
# own NIXBOOT, so re-installing works), or LUKS / LVM / Windows / ZFS partitions.
# Needs no mounting, so it also finds Pop!_OS from a live CD, where nothing of it is mounted.
os_problem() { # DISK -> reason, or nothing
    local d=$1 p fstype entry
    while read -r p; do
        fstype=$(lsblk -dno FSTYPE "$p")
        case $fstype in
        crypto_LUKS | LVM2_member | ntfs | BitLocker | zfs_member)
            echo "$d holds another OS or encrypted data: $p is $fstype" && return
            ;;
        esac
        [[ $(lsblk -dno LABEL "$p") == NIXBOOT ]] && continue
        entry=$(boot_entry_of "$p")
        [[ -n $entry ]] && echo "$d holds another OS: $p is the boot partition of \"$entry\"" && return
    done < <(parts_of "$d")
    return 0
}
is_sys_disk() { grep -qxF "$1" <<<"$SYS_DISKS"; }
mounted_in() { lsblk -nro MOUNTPOINTS "$1" | grep -v '^$' | sort -u | paste -sd' ' -; } # DEV -> "mp mp"
disk_ok() { # DISK [allow_mounted] -> refusal reason, or nothing
    local d=$1 t
    [[ -b $d ]] || { echo "$d is not a block device" && return; }
    t=$(lsblk -dno TYPE "$d")
    [[ $t == disk || ($t == loop && -n ${NIXOS_INSTALL_ALLOW_LOOP:-}) ]] || { echo "$d is a $t, not a whole disk" && return; }
    is_sys_disk "$d" && echo "$d is the disk the running system boots from" && return
    [[ -n ${2:-} ]] || { [[ -n $(mounted_in "$d") ]] && echo "$d is in use (mounted on $(mounted_in "$d")): unmount it first" && return; }
    return 0
}
# gpt_check DISK: sets GPT_PROBLEM (why it can't get GPT partitions, or empty) and NEED_GPT.
# Not called as $(...): NEED_GPT would only be set in that subshell
gpt_or_convertible() { # DISK -> reason, or nothing (use gpt_check to also get NEED_GPT)
    local d=$1 pt first last total
    NEED_GPT=""
    pt=$(lsblk -dno PTTYPE "$d")
    [[ $pt == gpt ]] && return 0
    [[ $pt == dos ]] || { echo "$d has no partition table (erase it instead)" && return; }
    # MBR -> GPT in place needs 34 free sectors at the start and 33 at the end
    first=$(partx -g -o START "$d" 2>/dev/null | sort -n | head -1)
    last=$(partx -g -o END "$d" 2>/dev/null | sort -n | tail -1)
    total=$(($(blockdev --getsz "$d" 2>/dev/null || sudo blockdev --getsz "$d")))
    [[ -z $first || $first -ge 34 ]] || { echo "$d is MBR and its first partition starts too early to convert it to GPT" && return; }
    [[ -z $last || $last -le $((total - 34)) || -n ${SHRINKING:-} ]] ||
        { echo "$d is MBR and its last partition ends too close to the end to convert it to GPT" && return; }
    NEED_GPT=1
}
gpt_check() {
    GPT_PROBLEM=$(gpt_or_convertible "$1")
    NEED_GPT=""
    [[ -z $GPT_PROBLEM && $(lsblk -dno PTTYPE "$1") == dos ]] && NEED_GPT=1
    return 0
}
# Free regions in a disk's partition table, largest first: "START END SECTORS" (logical sectors)
free_regions() { sudo sfdisk -F "$1" 2>/dev/null | awk '/^ *[0-9]+ +[0-9]+ +[0-9]+ / { print $1, $2, $3 }' | sort -k3,3nr; }
sector_size() { lsblk -dno LOG-SEC "$1" | tr -d ' '; }
describe() { # DEVICE -> "sda3      400.5G  ext4   nixos      (WDC WDS100T1B0B)"
    local d=$1 disk=$1 model
    [[ $(lsblk -dno TYPE "$d") == part ]] && disk=/dev/$(lsblk -dno PKNAME "$d")
    model=$(lsblk -dno MODEL "$disk" 2>/dev/null | sed 's/ *$//')
    printf '%-10s %7s  %-11s %-10s %s' "$(basename "$d")" "$(lsblk -dno SIZE "$d" | tr -d ' ')" \
        "$(lsblk -dno FSTYPE "$d")" "$(lsblk -dno LABEL "$d" 2>/dev/null)" "${model:+($model)}"
}
contents() { # DISK -> one line per partition: name size fstype label [mounted on X, N used] [boot entry]
    local p mp used entry
    while read -r p; do
        mp=$(mounted_in "$p")
        used=""
        [[ -n $mp && $mp != "[SWAP]" ]] && used=$(df -h --output=used "$p" 2>/dev/null | tail -1 | tr -d ' ')
        entry=$(boot_entry_of "$p")
        printf '  %s%s%s\n' "$(describe "$p" | sed 's/ *(.*)$//')" "${mp:+  mounted on $mp${used:+, $used used}}" "${entry:+  <- boot entry \"$entry\"}"
    done < <(parts_of "$1")
}

# --- host -------------------------------------------------------------------------------------
HOSTS=$(sed -n 's/^ *\([A-Za-z0-9_-]*\) *= *mkHost "\([^"]*\)".*/\1 \2/p' "$NIXOS_DIR/flake.nix")
if [[ -z $HOST ]]; then
    if [[ -z $LIVE && -f "$NIXOS_DIR/hosts/$(hostname).nix" ]] && grep -q "^$(hostname) " <<<"$HOSTS"; then
        HOST=$(hostname)
    elif [[ -n $GUIDED ]]; then
        items=()
        while read -r h s; do
            [[ $s == "$(uname -m)-linux" ]] && items+=("$h" "$h  ($s, hosts/$h.nix)")
        done <<<"$HOSTS"
        ui_menu "Host" "Which host from nixos/flake.nix?${LIVE:+ (live system: the hostname is not used)}" "${items[@]}"
        HOST=$REPLY
    else
        die "pass --host (one of: $(awk '{ printf "%s ", $1 }' <<<"$HOSTS"))"
    fi
fi
host_system=$(awk -v h="$HOST" '$1 == h { print $2 }' <<<"$HOSTS")
[[ -n $host_system ]] || die "host '$HOST' is not in nixos/flake.nix"
[[ $host_system == "$(uname -m)-linux" ]] || die "host '$HOST' is $host_system, this machine is $(uname -m)"
CRUMBS+=("host $HOST")

# --- the plan: MODE = erase | free | shrink | parts ---------------------------------------------
MODE="" OS_REASON="" NEED_GPT="" RELEASE=() FREE_START="" FREE_END=""

plan_free() { # DISK -> sets FREE_START / FREE_END from the largest free region, or dies
    local ss r
    ss=$(sector_size "$1")
    r=$(free_regions "$1" | head -1)
    [[ -n $r ]] || die "no free space on $1"
    read -r FREE_START FREE_END _ <<<"$r"
    (((FREE_END - FREE_START + 1) * ss >= (MIN_NIXOS_GIB + 1) * GiB)) ||
        die "the largest free space on $1 is $(gib $(((FREE_END - FREE_START + 1) * ss))) GiB; NixOS needs at least $((MIN_NIXOS_GIB + 1))"
}
shrink_limits() { # PARTITION -> SH_SIZE SH_USED SH_MIN (bytes): current size, used, smallest safe size
    local p=$1 bs blocks
    SH_SIZE=$(lsblk -bdno SIZE "$p")
    if [[ -n $(mounted_in "$p") ]]; then
        SH_USED=$(df -B1 --output=used "$p" | tail -1 | tr -d ' ')
    else
        bs=$(sudo dumpe2fs -h "$p" 2>/dev/null | awk -F: '/^Block size/ { gsub(/ /, "", $2); print $2 }')
        blocks=$(sudo resize2fs -P "$p" 2>/dev/null | awk -F: '/minimum size/ { gsub(/ /, "", $2); print $2 }')
        SH_USED=$((${bs:-4096} * ${blocks:-0}))
    fi
    # room for the data + 10 %, and at least 1 GiB more
    SH_MIN=$((SH_USED + SH_USED / 10 + GiB))
}

if [[ -n $GUIDED ]]; then
    # 1. the disk
    items=() hidden=()
    while read -r d; do
        why=$(disk_ok "$d" mounted)
        if [[ -n $why ]]; then
            [[ $why == *"running system"* ]] && hidden+=("$(basename "$d") (running system)")
            continue
        fi
        os=$(os_problem "$d")
        tag="empty"
        [[ -n $(parts_of "$d") ]] && tag="data: $(parts_of "$d" | while read -r p; do printf '%s ' "$(lsblk -dno FSTYPE "$p")"; done | sed 's/ *$//')"
        [[ -n $(mounted_in "$d") ]] && tag+=", mounted on $(mounted_in "$d")"
        [[ -n $os ]] && tag="ANOTHER OS: ${os#*: }"
        items+=("$d" "$(describe "$d")  [$tag]")
    done < <(lsblk -dnpo NAME,TYPE | awk -v loop="${NIXOS_INSTALL_ALLOW_LOOP:+loop}" '($2 == "disk" || $2 == loop) && $1 !~ /^\/dev\/(zram|ram)/ { print $1 }')
    ((${#items[@]})) || die "no disk available: the only disk(s) are the running system's (${hidden[*]})"
    ui_menu "Disk" "Which disk should NixOS go on?${hidden[*]:+$'\n'Not offered: ${hidden[*]}.}" "${items[@]}"
    DISK=$REPLY
    CRUMBS+=("$(basename "$DISK")")
    OS_REASON=$(os_problem "$DISK")

    # 2. the layout, among what this disk allows
    items=(erase "Erase the whole disk: 1 GiB EFI + NixOS on the rest")
    if [[ -z $OS_REASON ]]; then
        if [[ -z $(gpt_or_convertible "$DISK") ]]; then
            r=$(free_regions "$DISK" | head -1)
            if [[ -n $r ]]; then
                read -r _ _ secs <<<"$r"
                ((secs * $(sector_size "$DISK") >= (MIN_NIXOS_GIB + 1) * GiB)) &&
                    items+=(free "Use the free space ($(gib $((secs * $(sector_size "$DISK")))) GiB), keep all partitions")
            fi
            SHRINKING=1
            if [[ -z $(gpt_or_convertible "$DISK") ]]; then
                for p in $(parts_of "$DISK"); do
                    [[ $(lsblk -dno FSTYPE "$p") == ext4 ]] && items+=(shrink "Shrink a partition (ext4) and use the space it frees") && break
                done
            fi
            SHRINKING=""
        fi
        [[ $(lsblk -dno PTTYPE "$DISK") == gpt ]] && [[ -n $(parts_of "$DISK" | while read -r p; do [[ $(lsblk -dno PARTTYPE "$p") == "$EFI_TYPE" ]] && echo y; done) ]] &&
            items+=(parts "Use two existing partitions: an EFI one + one for NixOS (both formatted)")
    fi
    text="$(describe "$DISK")"$'\n\n'"$(contents "$DISK")"
    [[ -n $OS_REASON ]] && text+=$'\n\n'"It holds another OS, so the only choice is a full erase."
    ui_menu "Layout" "$text" "${items[@]}"
    MODE=$REPLY
    CRUMBS+=("$MODE")

    case $MODE in
    erase) ;;
    free)
        plan_free "$DISK"
        ss=$(sector_size "$DISK")
        avail=$((((FREE_END - FREE_START + 1) * ss - GiB) / GiB))
        while true; do
            ui_input "NixOS size" "Size of the NixOS partition in GiB ($MIN_NIXOS_GIB to $avail; empty = all $avail):" ""
            [[ -z $REPLY ]] && NIXOS_GIB="" && break
            [[ $REPLY =~ ^[0-9]+$ ]] && ((REPLY >= MIN_NIXOS_GIB && REPLY <= avail)) && NIXOS_GIB=$REPLY && break
        done
        ;;
    shrink)
        items=()
        for p in $(parts_of "$DISK"); do
            [[ $(lsblk -dno FSTYPE "$p") == ext4 ]] || continue
            shrink_limits "$p"
            ((SH_SIZE - SH_MIN >= (MIN_NIXOS_GIB + 1) * GiB)) || continue
            items+=("$p" "$(describe "$p")  [$(gib "$SH_USED") GiB used, can free up to $(gib $((SH_SIZE - SH_MIN))) GiB]")
        done
        ((${#items[@]})) || die "no ext4 partition on $DISK can free the $((MIN_NIXOS_GIB + 1)) GiB NixOS needs"
        ui_menu "Shrink" "Which partition should give space to NixOS? Its data is kept." "${items[@]}"
        SHRINK_PART=$REPLY
        shrink_limits "$SHRINK_PART"
        lo=$(((SH_MIN + GiB - 1) / GiB)) hi=$(((SH_SIZE - (MIN_NIXOS_GIB + 1) * GiB) / GiB))
        while true; do
            ui_input "Shrink $(basename "$SHRINK_PART")" "$(basename "$SHRINK_PART") is $(gib "$SH_SIZE") GiB with $(gib "$SH_USED") GiB used.
How many GiB should it keep? ($lo to $hi; NixOS gets the rest)" "$(((lo + hi) / 2))"
            [[ $REPLY =~ ^[0-9]+$ ]] && ((REPLY >= lo && REPLY <= hi)) && SHRINK_GIB=$REPLY && break
        done
        ;;
    parts)
        efi=() root=()
        for p in $(parts_of "$DISK"); do
            [[ -n $(mounted_in "$p") ]] && continue
            if [[ $(lsblk -dno PARTTYPE "$p") == "$EFI_TYPE" ]]; then efi+=("$p" "$(describe "$p")"); else root+=("$p" "$(describe "$p")"); fi
        done
        ((${#efi[@]})) || die "no unmounted EFI partition on $DISK"
        ((${#root[@]})) || die "no other unmounted partition on $DISK for NixOS"
        ui_menu "EFI partition" "Partition for NixOS's boot loader (it will be FORMATTED):" "${efi[@]}"
        BOOT_PART=$REPLY
        ui_menu "NixOS partition" "Partition for NixOS itself (it will be FORMATTED):" "${root[@]}"
        ROOT_PART=$REPLY
        ;;
    esac
else
    if [[ -n $DISK ]]; then
        MODE=erase
    elif [[ -n $FREE_DISK ]]; then
        MODE=free DISK=$FREE_DISK
    elif [[ -n $SHRINK_PART ]]; then
        MODE=shrink DISK=/dev/$(lsblk -dno PKNAME "$SHRINK_PART" 2>/dev/null || true)
    else
        MODE=parts DISK=/dev/$(lsblk -dno PKNAME "$ROOT_PART" 2>/dev/null || true)
    fi
fi

# --- validate the plan (guided or not, the same checks) -----------------------------------------
[[ $DISK != /dev/ ]] || die "not a partition: ${SHRINK_PART:-$ROOT_PART}"
OS_REASON=$(os_problem "$DISK")
case $MODE in
erase)
    problem=$(disk_ok "$DISK" ${GUIDED:+mounted})
    [[ -z $problem ]] || die "$problem"
    if [[ -n $OS_REASON && -z $GUIDED && ${NIXOS_INSTALL_ALLOW_OS_DISK:-} != "$DISK" ]]; then
        die "$OS_REASON. To erase it anyway: NIXOS_INSTALL_ALLOW_OS_DISK=$DISK"
    fi
    ;;
free | shrink | parts)
    problem=$(disk_ok "$DISK" mounted)
    [[ -z $problem ]] || die "$problem"
    [[ -z $OS_REASON ]] || die "$OS_REASON: NixOS is not installed next to another OS on the same disk; erase the disk or pick another"
    ;;
esac
case $MODE in
free)
    gpt_check "$DISK"
    [[ -z $GPT_PROBLEM ]] || die "$GPT_PROBLEM"
    plan_free "$DISK"
    if [[ -n $NIXOS_GIB ]]; then
        ((NIXOS_GIB >= MIN_NIXOS_GIB)) || die "--size: NixOS needs at least $MIN_NIXOS_GIB GiB"
        (((FREE_END - FREE_START + 1) * $(sector_size "$DISK") >= (NIXOS_GIB + 1) * GiB)) || die "--size $NIXOS_GIB does not fit in the free space"
    fi
    ;;
shrink)
    [[ $(lsblk -dno TYPE "$SHRINK_PART") == part ]] || die "$SHRINK_PART is not a partition"
    [[ $(lsblk -dno FSTYPE "$SHRINK_PART") == ext4 ]] || die "only ext4 partitions can be shrunk ($SHRINK_PART is $(lsblk -dno FSTYPE "$SHRINK_PART"))"
    [[ -z $(lsblk -nro NAME "$SHRINK_PART" | tail -n +2) ]] || die "$SHRINK_PART has volumes on top of it (LUKS / LVM)"
    SHRINKING=1
    gpt_check "$DISK"
    SHRINKING=""
    [[ -z $GPT_PROBLEM ]] || die "$GPT_PROBLEM"
    shrink_limits "$SHRINK_PART"
    ((SHRINK_GIB * GiB >= SH_MIN)) || die "$SHRINK_PART holds $(gib "$SH_USED") GiB: keep at least $(((SH_MIN + GiB - 1) / GiB)) GiB"
    ((SH_SIZE - SHRINK_GIB * GiB >= (MIN_NIXOS_GIB + 1) * GiB)) || die "keeping $SHRINK_GIB GiB leaves less than $((MIN_NIXOS_GIB + 1)) GiB for NixOS"
    [[ -z $NIXOS_GIB ]] || ((SH_SIZE - SHRINK_GIB * GiB >= (NIXOS_GIB + 1) * GiB)) || die "--size $NIXOS_GIB does not fit in what --keep $SHRINK_GIB frees"
    [[ -n $(mounted_in "$SHRINK_PART") ]] && RELEASE+=("$SHRINK_PART")
    ;;
parts)
    [[ $BOOT_PART != "$ROOT_PART" ]] || die "--boot-part and --root-part are the same partition"
    for p in "$BOOT_PART" "$ROOT_PART"; do
        [[ -b $p && $(lsblk -dno TYPE "$p") == part ]] || die "$p is not a partition"
        [[ /dev/$(lsblk -dno PKNAME "$p") == "$DISK" ]] || die "--boot-part and --root-part must be on the same disk"
        [[ -z $(mounted_in "$p") ]] || die "$p is in use (mounted on $(mounted_in "$p"))"
    done
    [[ $(lsblk -dno PTTYPE "$DISK") == gpt ]] || die "$DISK is not GPT (systemd-boot needs a GPT EFI partition)"
    [[ $(lsblk -dno PARTTYPE "$BOOT_PART") == "$EFI_TYPE" ]] || die "$BOOT_PART is not an EFI system partition (GPT type EF00)"
    BOOT_DEV=$BOOT_PART ROOT_DEV=$ROOT_PART
    ;;
erase)
    for p in $(parts_of "$DISK"); do [[ -n $(mounted_in "$p") ]] && RELEASE+=("$p"); done
    ;;
esac
# Things mounted on volumes inside a partition (LUKS / LVM) can't be released safely here
for p in ${RELEASE[@]+"${RELEASE[@]}"}; do
    [[ -z $(lsblk -nro NAME "$p" | tail -n +2) ]] || die "$p has open LUKS / LVM volumes on it: close them first"
done

# --- user, timezone, password -------------------------------------------------------------------
if [[ -z $USERNAME ]]; then
    if [[ -z $LIVE ]]; then
        USERNAME=$(id -un)
    elif [[ -n $GUIDED ]]; then
        while [[ ! $USERNAME =~ ^[a-z_][a-z0-9._-]*$ ]]; do
            ui_input "User" "NixOS user name (lowercase):" "" && USERNAME=$REPLY
        done
    else
        die "on a live CD, pass --user NAME"
    fi
fi
if [[ -z $TIMEZONE ]]; then
    [[ -z $LIVE ]] && TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    if [[ -z $TIMEZONE && -n $GUIDED ]]; then
        ui_input "Timezone" "Timezone (Region/City):" America/Toronto && TIMEZONE=$REPLY
    fi
    TIMEZONE=${TIMEZONE:-America/Toronto}
fi
[[ -e /usr/share/zoneinfo/$TIMEZONE || -n $LIVE ]] || warn "unknown timezone '$TIMEZONE'"
PASSWORD=${NIXOS_PASSWORD:-}
while [[ -z $PASSWORD ]]; do
    ui_password "Password" "Password for $USERNAME on NixOS:"
    p1=$REPLY
    ui_password "Password" "Again:"
    if [[ -n $p1 && $p1 == "$REPLY" ]]; then PASSWORD=$p1; else ui_msg "Password" "Empty, or they do not match. Try again."; fi
done

# --- Wi-Fi to copy: NixOS is online at its first boot (init.sh, updates and the network menu need it)
WIFI_UUIDS=() WIFI_NAMES=() WIFI_NOTE=""
EXPORT_WIFI=$NIXOS_DIR/export-wifi.sh
if ! command -v nmcli >/dev/null || ! saved=$(sudo bash "$EXPORT_WIFI" --list 2>/dev/null); then
    WIFI_NOTE="none (no NetworkManager here): connect on NixOS with nmtui"
elif [[ -z $saved ]]; then
    WIFI_NOTE="none saved here: connect on NixOS with nmtui"
else
    if [[ -n $GUIDED && -z $WIFI_ARG ]]; then
        items=()
        while IFS=$'\t' read -r u n a; do items+=("$u" "$n${a/yes/  (connected now)}" on); done <<<"$(sed 's/\tno$/\t/' <<<"$saved")"
        ui_checklist "Wi-Fi" "Copy these Wi-Fi networks (with their passwords) to NixOS, so it is online at its first boot?
Each is copied without its access-point lock, so a router that steers the card to another band still works." "${items[@]}"
        picked=" $REPLY "
    else
        picked=""
        case ${WIFI_ARG:-active} in
        none) ;;
        all) picked=" $(cut -f1 <<<"$saved" | paste -sd' ' -) " ;;
        active) picked=" $(awk -F'\t' '$3 == "yes" { print $1 }' <<<"$saved" | paste -sd' ' -) " ;;
        *)
            IFS=, read -ra want <<<"$WIFI_ARG"
            for w in "${want[@]}"; do
                u=$(awk -F'\t' -v n="$w" '$2 == n { print $1; exit }' <<<"$saved")
                [[ -n $u ]] || die "--wifi: no saved Wi-Fi named \"$w\" (saved: $(cut -f2 <<<"$saved" | paste -sd, -))"
                picked+=" $u"
            done
            picked+=" "
            ;;
        esac
    fi
    while IFS=$'\t' read -r u n _; do
        [[ $picked == *" $u "* ]] && WIFI_UUIDS+=("$u") && WIFI_NAMES+=("$n")
    done <<<"$saved"
    ((${#WIFI_UUIDS[@]})) || WIFI_NOTE="none: connect on NixOS with nmtui"
fi

# --- SSH keys to copy (optional): git push / ssh work on NixOS without new keys -------------------
SSH_SRC=$HOME/.ssh SSH_ITEMS=() SSH_NOTE=""
ssh_saved=$(bash "$NIXOS_DIR/copy-ssh.sh" --list "$SSH_SRC" 2>/dev/null || true)
if [[ -z $ssh_saved ]]; then
    SSH_NOTE="none (nothing in $SSH_SRC)"
else
    picked=" "
    if [[ -n $GUIDED && -z $SSH_ARG ]]; then
        items=()
        while IFS=$'\t' read -r n d; do items+=("$n" "$(printf '%-18s %s' "$n" "$d")" on); done <<<"$ssh_saved"
        ui_checklist "SSH keys" "Copy these from $SSH_SRC to your NixOS home? (optional; untick all with a)
Private keys are copied as they are, with their passphrase if they have one, readable by you only." "${items[@]}"
        picked=" $REPLY "
    else
        case ${SSH_ARG:-none} in
        none) ;;
        all) picked=" $(cut -f1 <<<"$ssh_saved" | paste -sd' ' -) " ;;
        *)
            IFS=, read -ra want <<<"$SSH_ARG"
            for w in "${want[@]}"; do
                grep -qxF "$w" < <(cut -f1 <<<"$ssh_saved") || die "--ssh: no key or ssh file named \"$w\" in $SSH_SRC (there: $(cut -f1 <<<"$ssh_saved" | paste -sd, -))"
                picked+="$w "
            done
            ;;
        esac
    fi
    while IFS=$'\t' read -r n _; do [[ $picked == *" $n "* ]] && SSH_ITEMS+=("$n"); done <<<"$ssh_saved"
    ((${#SSH_ITEMS[@]})) || SSH_NOTE="none"
fi

# --- summary, warnings, confirmation --------------------------------------------------------------
model=$(lsblk -dno MODEL "$DISK" 2>/dev/null | sed 's/ *$//' || true)
disk_line="$DISK${model:+  $model}  $(lsblk -dno SIZE "$DISK" | tr -d ' ')"
lines=("Host      $HOST ($host_system)" "User      $USERNAME" "Timezone  $TIMEZONE" "Disk      $disk_line" "")
case $MODE in
erase)
    lines+=("ERASED    everything on $DISK" "          -> new GPT: 1 GiB EFI (NIXBOOT) + NixOS (nixos) on the rest")
    CONFIRM=$(basename "$DISK")
    ;;
free)
    sz=${NIXOS_GIB:+$NIXOS_GIB GiB}
    lines+=("New       1 GiB EFI (NIXBOOT) + NixOS (nixos) ${sz:-on all $(gib $(((FREE_END - FREE_START + 1) * $(sector_size "$DISK") - GiB))) GiB} in the free space")
    CONFIRM=$(basename "$DISK")
    ;;
shrink)
    lines+=("Shrunk    $(basename "$SHRINK_PART")  $(gib "$SH_SIZE") -> $SHRINK_GIB GiB, data kept ($(gib "$SH_USED") GiB used)"
        "New       1 GiB EFI (NIXBOOT) + NixOS (nixos) ${NIXOS_GIB:+$NIXOS_GIB GiB }in the freed space")
    CONFIRM=$(basename "$SHRINK_PART")
    ;;
parts)
    lines+=("Formatted ${BOOT_DEV##*/}  $(lsblk -dno SIZE "$BOOT_DEV" | tr -d ' ')  -> EFI (NIXBOOT)"
        "Formatted ${ROOT_DEV##*/}  $(lsblk -dno SIZE "$ROOT_DEV" | tr -d ' ')  -> NixOS (nixos)")
    CONFIRM=$(basename "$ROOT_DEV")
    ;;
esac
if [[ $MODE != erase ]]; then
    for p in $(parts_of "$DISK"); do
        [[ $p == "${BOOT_DEV:-}" || $p == "${ROOT_DEV:-}" || $p == "$SHRINK_PART" ]] && continue
        lines+=("Kept      $(describe "$p" | sed 's/ *(.*)$//')")
    done
fi
[[ -n $NEED_GPT ]] && lines+=("Converted $DISK MBR -> GPT in place (partitions kept)")
lines+=("" "Wi-Fi     ${WIFI_NOTE:-$(IFS=,; echo "${WIFI_NAMES[*]}" | sed 's/,/, /g')}"
    "SSH       ${SSH_NOTE:-$(IFS=,; echo "${SSH_ITEMS[*]}" | sed 's/,/, /g') -> ~/.ssh}"
    "Dotfiles  this checkout -> ~/nodestack/dotfiles, configs linked (Hyprland + Caelestia ready)" "")
for p in ${RELEASE[@]+"${RELEASE[@]}"}; do lines+=("Unmounted $(basename "$p") from $(mounted_in "$p")${MODE:+$([[ $MODE == shrink ]] && echo ', remounted after')}"); done
while read -r d; do
    [[ $d == "$DISK" ]] && continue
    if is_sys_disk "$d"; then lines+=("Untouched $d (running system)"); elif [[ -n $(os_problem "$d") ]]; then lines+=("Untouched $d (another OS)"); fi
done < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }')

# What an erase destroys, spelled out
STALE_UUIDS=()
if [[ $MODE == erase && -n $(parts_of "$DISK") ]]; then
    CONFIRM="erase $(basename "$DISK")"
    for p in $(parts_of "$DISK"); do
        u=$(lsblk -dno PARTUUID "$p")
        [[ -n $u && -n $(boot_entry_of "$p") ]] && STALE_UUIDS+=("$u")
    done
    warning="EVERYTHING on $DISK will be destroyed:"$'\n\n'"$(contents "$DISK")"
    [[ -n $OS_REASON ]] && warning+=$'\n\n'"This is a clean install over an existing system: ${OS_REASON#*: }."$'\n'"That system and all its files will be gone, and it will no longer boot."
    ((${#STALE_UUIDS[@]})) && warning+=$'\n'"Its firmware boot entries will be removed after the install."
    [[ -z $LIVE ]] && grep -qE "$(parts_of "$DISK" | while read -r p; do lsblk -dno UUID "$p"; done | grep . | paste -sd'|' -)" /etc/fstab 2>/dev/null &&
        warning+=$'\n'"This system's /etc/fstab mounts partitions of $DISK: remove those lines after the install."
    warning+=$'\n\n'"Make sure anything you need from it is backed up."
    if [[ -n ${NIXOS_INSTALL_YES:-} ]]; then
        printf '%s\n' "$warning" >&2
    else
        ui_yesno "WARNING: data loss" "$warning" "I understand" "Cancel" || die "cancelled"
    fi
fi

summary=$(printf '%s\n' "${lines[@]}")
if [[ $UI == tui ]]; then
    ui_yesno "Summary" "$summary"$'\n\n'"Continue? You will be asked to type \"$CONFIRM\"." "Continue" "Cancel" || die "cancelled"
else
    echo
    box "Install NixOS${LIVE:+ (from a live system)}" "${lines[@]}"
fi
if [[ -z ${NIXOS_INSTALL_YES:-} ]]; then
    if [[ $UI == tui ]]; then
        ui_input "Confirm" "Type  $CONFIRM  to start. Nothing has been changed so far." ""
    else
        read -rp "Type ${B}$CONFIRM${R} to continue: " REPLY
    fi
    [[ $REPLY == "$CONFIRM" ]] || die "cancelled (typed \"$REPLY\", expected \"$CONFIRM\")"
fi
if [[ $UI == tui ]]; then # the summary was on a TUI screen: keep it in the scrollback
    clear
    box "Install NixOS${LIVE:+ (from a live system)}" "${lines[@]}"
fi

# --- 1. Nix (only if missing) -------------------------------------------------------------------
step "Nix"
# Installed earlier but not in this shell's PATH yet (e.g. a terminal opened before the install)
if ! command -v nix >/dev/null && [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck source=/dev/null
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if ! command -v nix >/dev/null; then
    info "Installing Nix (multi-user: /nix + nix-daemon)"
    [[ -n $LIVE ]] && warn "on a live CD, /nix lives in RAM: only the install tools go there, the system is built on the target"
    sh <(curl -fsSL https://nixos.org/nix/install) --daemon --yes
    # shellcheck source=/dev/null
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
    echo "  already installed: $(nix --version)"
fi

# --- 2. tools from the nixpkgs revision pinned in flake.lock -----------------------------------
# (the root's nixpkgs input, e.g. node "nixpkgs_2", not the first "nixpkgs" node; nix reads
# the JSON, since the NixOS ISO has no python3 or jq)
rev=$(LOCK="$NIXOS_DIR/flake.lock" "${NIX[@]}" eval --raw --impure --expr \
    'let n = (builtins.fromJSON (builtins.readFile (builtins.getEnv "LOCK"))).nodes; in n.${n.root.inputs.nixpkgs}.locked.rev' \
    2>/dev/null || true)
[[ -n $rev ]] || die "no nixpkgs revision in nixos/flake.lock"
step "nixos-install and disk tools (nixpkgs ${rev:0:7})"
tools=$("${NIX[@]}" build --no-link --print-out-paths \
    "github:nixos/nixpkgs/$rev#nixos-install-tools" "github:nixos/nixpkgs/$rev#parted" \
    "github:nixos/nixpkgs/$rev#dosfstools" "github:nixos/nixpkgs/$rev#e2fsprogs" \
    "github:nixos/nixpkgs/$rev#gptfdisk" "github:nixos/nixpkgs/$rev#efibootmgr")
TOOL_PATH=""
for t in $tools; do
    if [[ -d $t/bin ]]; then TOOL_PATH+="$t/bin:"; fi
    if [[ -d $t/sbin ]]; then TOOL_PATH+="$t/sbin:"; fi
done
TOOL_PATH+="$(dirname "$(command -v nix)"):$PATH"
as_root() { sudo env "PATH=$TOOL_PATH" "$@"; }
echo "  ok"

# --- 3. the disk ---------------------------------------------------------------------------------
part() { if [[ $1 =~ [0-9]$ ]]; then echo "${1}p$2"; else echo "${1}$2"; fi; } # DISK N -> partition
reread() { # make the kernel see the new table, also when other partitions are mounted
    as_root partprobe "$DISK" 2>/dev/null || as_root partx -u "$DISK" 2>/dev/null || true
    as_root partx -a "$DISK" 2>/dev/null || true
    sudo udevadm settle
}
wait_dev() { # DEV
    local i
    for i in $(seq 1 20); do [[ -b $1 ]] && return 0; sleep 0.5; done
    die "the kernel does not show $1 yet: reboot, then re-run with --boot-part / --root-part"
}
fsck_ok() { # e2fsck ARGS... PART: exit codes 0-3 are fine (3 = errors corrected)
    local rc=0
    as_root e2fsck "$@" || rc=$?
    ((rc < 4)) || die "e2fsck failed (exit $rc) on ${*: -1}: stopping, investigate before going on"
}
free_numbers() { # -> the two lowest unused partition numbers
    local used n out=()
    used=$(as_root sgdisk -p "$DISK" | awk '/^ +[0-9]+ / { print $1 }')
    for n in $(seq 1 128); do grep -qx "$n" <<<"$used" || out+=("$n"); ((${#out[@]} == 2)) && break; done
    echo "${out[@]}"
}
make_nixos_parts() { # START END (logical sectors of a free region) -> BOOT_DEV ROOT_DEV
    local ss al s e bend rend n1 n2
    ss=$(sector_size "$DISK") al=$((1048576 / ss))
    s=$((($1 + al - 1) / al * al)) e=$2
    bend=$((s + GiB / ss - 1))
    if [[ -n $NIXOS_GIB ]]; then rend=$((bend + NIXOS_GIB * GiB / ss)); else rend=$e; fi
    ((rend <= e && rend > bend)) || die "the NixOS partitions do not fit between sectors $1 and $2"
    read -r n1 n2 <<<"$(free_numbers)"
    info "Creating $(basename "$(part "$DISK" "$n1")") (1 GiB EFI) and $(basename "$(part "$DISK" "$n2")") (NixOS, $(gib $(((rend - bend) * ss))) GiB)"
    as_root sgdisk -n "$n1:$s:$bend" -t "$n1:EF00" -c "$n1:NIXBOOT" \
        -n "$n2:$((bend + 1)):$rend" -t "$n2:8300" -c "$n2:nixos" "$DISK" >/dev/null ||
        warn "sgdisk could not make the kernel re-read the table (partitions in use): trying partx"
    reread
    BOOT_DEV=$(part "$DISK" "$n1") ROOT_DEV=$(part "$DISK" "$n2")
    wait_dev "$BOOT_DEV" && wait_dev "$ROOT_DEV"
}
convert_gpt() {
    local before after
    before=$(as_root partx -g -o NR,START,END "$DISK")
    info "Converting $DISK from MBR to GPT (in place)"
    as_root sgdisk -g "$DISK" >/dev/null || warn "sgdisk could not make the kernel re-read the table: trying partx"
    reread
    after=$(as_root partx -g -o NR,START,END "$DISK")
    [[ $before == "$after" ]] || die "partitions moved during the GPT conversion (before: $before / after: $after). Stopping: restore the table from the backup in $TABLE_BACKUP"
    as_root sgdisk -v "$DISK" | grep -q 'No problems found' || die "sgdisk -v reports problems on $DISK: stopping"
}
release() { # unmount what the plan said would be unmounted
    local p mp
    for p in ${RELEASE[@]+"${RELEASE[@]}"}; do
        for mp in $(mounted_in "$p"); do
            if [[ $mp == "[SWAP]" ]]; then sudo swapoff "$p"; else
                info "Unmounting $mp"
                sudo umount "$mp" || {
                    sudo fuser -vm "$mp" || true
                    die "$mp is busy: close the programs above (shells cd'ed into it, file managers), then re-run. Nothing was changed."
                }
            fi
        done
    done
}

TABLE_BACKUP=$HOME/$(basename "$DISK")-partition-table-$(date +%Y%m%d-%H%M%S).sfdisk
step "Disk: $MODE $DISK"
REMOUNT=""
[[ $MODE == shrink && -n $(mounted_in "$SHRINK_PART") ]] && REMOUNT=$(mounted_in "$SHRINK_PART")
release
if [[ $MODE != erase ]]; then
    # shellcheck disable=SC2024 # written as you, into your home
    sudo sfdisk -d "$DISK" >"$TABLE_BACKUP" 2>/dev/null && echo "  partition table saved to $TABLE_BACKUP"
fi
case $MODE in
erase)
    info "Wiping signatures and creating a new GPT on $DISK"
    for p in $(parts_of "$DISK"); do as_root wipefs -aq "$p" || true; done
    as_root wipefs -aq "$DISK"
    as_root parted -s "$DISK" -- mklabel gpt \
        mkpart NIXBOOT fat32 1MiB 1GiB set 1 esp on \
        mkpart nixos ext4 1GiB 100%
    reread
    BOOT_DEV=$(part "$DISK" 1) ROOT_DEV=$(part "$DISK" 2)
    wait_dev "$BOOT_DEV" && wait_dev "$ROOT_DEV"
    ;;
free)
    [[ -n $NEED_GPT ]] && convert_gpt
    plan_free "$DISK"
    make_nixos_parts "$FREE_START" "$FREE_END"
    ;;
shrink)
    ss=$(sector_size "$DISK")
    n=$(cat "/sys/class/block/$(basename "$SHRINK_PART")/partition")
    start=$(as_root sfdisk -d "$DISK" | awk -v p="$SHRINK_PART" '$1 == p { for (i = 1; i <= NF; i++) if ($i == "start=") { gsub(",", "", $(i+1)); print $(i+1) } }')
    [[ $start =~ ^[0-9]+$ ]] || die "could not read the start of $SHRINK_PART"
    info "Checking the filesystem on $SHRINK_PART"
    fsck_ok -f -y "$SHRINK_PART"
    shrink_limits "$SHRINK_PART"
    ((SHRINK_GIB * GiB >= SH_MIN)) || die "after the check, $SHRINK_PART needs at least $(((SH_MIN + GiB - 1) / GiB)) GiB: nothing was resized"
    info "Shrinking the filesystem to $((SHRINK_GIB * 1024 - 256)) MiB"
    as_root resize2fs "$SHRINK_PART" "$((SHRINK_GIB * 1024 - 256))M"
    info "Shrinking $SHRINK_PART to $SHRINK_GIB GiB (same start sector $start)"
    echo "$start,$((SHRINK_GIB * GiB / ss))" | as_root sfdisk --no-reread -q -N "$n" "$DISK"
    reread
    [[ -n $NEED_GPT ]] && convert_gpt
    info "Growing the filesystem back to fill $SHRINK_PART, and checking it"
    fsck_ok -f -y "$SHRINK_PART"
    as_root resize2fs "$SHRINK_PART"
    fsck_ok -f -n "$SHRINK_PART"
    region=$(free_regions "$DISK" | awk -v s="$((start + SHRINK_GIB * GiB / ss))" '$1 >= s && $1 <= s + 2048 { print; exit }')
    [[ -n $region ]] || die "could not find the space freed after $SHRINK_PART"
    read -r fs fe _ <<<"$region"
    make_nixos_parts "$fs" "$fe"
    if [[ -n $REMOUNT ]]; then
        sudo mount "$SHRINK_PART" "$REMOUNT" && echo "  remounted $SHRINK_PART on $REMOUNT"
    fi
    ;;
parts) echo "  using $BOOT_DEV and $ROOT_DEV as they are" ;;
esac

# --- 4. format + mount ---------------------------------------------------------------------------
step "Formatting $BOOT_DEV (EFI) and $ROOT_DEV (NixOS)"
for p in "$BOOT_DEV" "$ROOT_DEV"; do
    [[ /dev/$(lsblk -dno PKNAME "$p") == "$DISK" ]] || die "$p is not on $DISK: stopping"
    is_sys_disk "/dev/$(lsblk -dno PKNAME "$p")" && die "$p is on the running system's disk: stopping"
done
as_root mkfs.fat -F 32 -n NIXBOOT "$BOOT_DEV" >/dev/null
as_root mkfs.ext4 -qF -L nixos "$ROOT_DEV"
sudo mkdir -p "$MNT"
sudo mount "$ROOT_DEV" "$MNT"
sudo mkdir -p "$MNT/boot"
sudo mount -o umask=077 "$BOOT_DEV" "$MNT/boot"
trap 'sudo umount -R "$MNT" 2>/dev/null || true' EXIT
echo "  mounted on $MNT"
if [[ -n ${NIXOS_INSTALL_STOP_AFTER_DISK:-} ]]; then # tests only
    sudo umount -R "$MNT" && trap - EXIT
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,UUID "$DISK"
    exit 0
fi

# --- 5. config ------------------------------------------------------------------------------------
step "Writing $MNT/etc/nixos"
as_root bash "$NIXOS_DIR/write-config.sh" "$MNT" "$USERNAME" "$TIMEZONE"
# nixos-generate-config lists every active swap, including this system's
# (Pop!_OS: encrypted cryptswap; a live CD: zram), which NixOS would then wait for at boot
sudo sed -z -i 's/swapDevices[[:space:]]*=[[:space:]]*\[[^]]*\];/swapDevices = [ ];/' \
    "$MNT/etc/nixos/hardware-configuration.nix"

# --- 6. install -------------------------------------------------------------------------------------
step "nixos-install ${DIM}(the first build takes a while)${R}"
# On a live CD, /tmp is RAM: build in a temp dir on the target instead
tmp_env=()
if [[ -n $LIVE ]]; then
    sudo mkdir -p -m 1777 "$MNT/tmp"
    tmp_env=(TMPDIR="$MNT/tmp")
fi
extra=()
[[ -n ${NIXOS_INSTALL_NO_BOOTLOADER:-} ]] && extra+=(--no-bootloader) # tests only
as_root env ${tmp_env[@]+"${tmp_env[@]}"} nixos-install --root "$MNT" --flake "$MNT/etc/nixos#$HOST" --impure \
    --no-root-passwd --no-channel-copy --option experimental-features "nix-command flakes" \
    ${extra[@]+"${extra[@]}"}
[[ -z $LIVE ]] || { sudo rm -rf "$MNT/tmp" && sudo mkdir -m 1777 "$MNT/tmp"; }

# --- 7. user, dotfiles, boot entries ----------------------------------------------------------------
step "User $USERNAME, dotfiles, Wi-Fi, SSH keys, boot entries"
# Inside the chroot, this system's PATH (/usr/bin, the tools' store paths) does not exist
in_nixos() { as_root nixos-enter --root "$MNT" -c "PATH=/nix/var/nix/profiles/system/sw/bin; $1" 2> >(grep -v '^setting up /etc' >&2); }
echo "$USERNAME:$PASSWORD" | in_nixos chpasswd
uid_gid=$(in_nixos "id -u $USERNAME; id -g $USERNAME" | grep -E '^[0-9]+$' | paste -sd: -)
[[ $uid_gid =~ ^[0-9]+:[0-9]+$ ]] || die "could not read the uid / gid of $USERNAME on NixOS"
sudo mkdir -p "$MNT/home/$USERNAME/nodestack"
sudo rm -rf "$MNT/home/$USERNAME/nodestack/dotfiles"
sudo cp -a "$DOTFILES" "$MNT/home/$USERNAME/nodestack/dotfiles"
sudo chown -R "$uid_gid" "$MNT/home/$USERNAME"
# Link the configs now, so the first login has Hyprland's config (it starts Caelestia)
# even if init.sh can't run yet, e.g. without network
info "Linking the dotfiles into /home/$USERNAME"
sudo bash "$NIXOS_DIR/link-dotfiles.sh" --root "$MNT" --user "$USERNAME" --owner "$uid_gid"
if ((${#SSH_ITEMS[@]})); then
    info "Copying SSH keys"
    sudo bash "$NIXOS_DIR/copy-ssh.sh" "$SSH_SRC" "$MNT/home/$USERNAME/.ssh" "$uid_gid" "${SSH_ITEMS[@]}"
fi
if ((${#WIFI_UUIDS[@]})); then
    info "Copying Wi-Fi networks"
    sudo bash "$EXPORT_WIFI" "$MNT/etc/NetworkManager/system-connections" "${WIFI_UUIDS[@]}"
fi
# An erased OS leaves firmware entries pointing at partitions that no longer exist
for u in ${STALE_UUIDS[@]+"${STALE_UUIDS[@]}"}; do
    as_root efibootmgr -v | grep -i "HD([0-9]*,GPT,$u" | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p' | while read -r num; do
        info "Removing the firmware boot entry Boot$num (its partition was erased)"
        as_root efibootmgr -q -b "$num" -B
    done
done

sudo umount -R "$MNT"
trap - EXIT

# --- done -------------------------------------------------------------------------------------------
boot_now=$(as_root efibootmgr 2>/dev/null || true)
nixos_entry=$(sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Linux Boot Manager.*/\1/p' <<<"$boot_now" | head -1)
order=$(sed -n 's/^BootOrder: //p' <<<"$boot_now")
done_lines=()
[[ -n $LIVE ]] && done_lines+=("0. Remove the live CD / USB")
done_lines+=("1. Reboot, open the firmware boot menu (F8 / F11 / F12) and pick"
    "     \"Linux Boot Manager\" on ${model:-$DISK} ($DISK)"
    "2. Log in as $USERNAME, then run:"
    "     bash ~/nodestack/dotfiles/nixos/init.sh"
    "3. Change the password if it was a temporary one: passwd")
[[ -f $TABLE_BACKUP ]] && done_lines+=("" "Old partition table of $DISK: $TABLE_BACKUP")
((${#WIFI_UUIDS[@]})) || done_lines+=("" "No Wi-Fi was copied: on NixOS, connect with nmtui (or plug in a cable)")
if [[ -n $order ]]; then
    done_lines+=("" "Boot order now: $order${nixos_entry:+ (NixOS = $nixos_entry)}")
    IFS=, read -ra o <<<"$order"
    if [[ -n $nixos_entry && ${o[0]} == "$nixos_entry" && ${#o[@]} -gt 1 ]]; then
        swapped=("${o[1]}" "${o[0]}" "${o[@]:2}")
        done_lines+=("To start the other OS by default instead (check with: efibootmgr):"
            "     sudo efibootmgr -o $(IFS=,; echo "${swapped[*]}")")
    fi
fi
echo
box "NixOS is installed on $DISK" "${done_lines[@]}"
echo
