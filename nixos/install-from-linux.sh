#!/usr/bin/env bash
# =============================================================================
# Install NixOS onto a disk, either from a running Linux (another distro) for a
# dual boot without a live USB, or from a live CD / USB (NixOS ISO, Ubuntu...).
# The running system is not modified, apart from Nix being installed if it's
# missing (/nix + the nix-daemon service). The running system's disk can't be
# picked; on a disk holding another OS, NixOS only goes in place of it (a full
# erase, or deleting its partitions), behind a warning that lists what is destroyed.
#
#   nixos/install-from-linux.sh                 guided, arrow-key menus: host, disk, layout, user, password
#   nixos/install-from-linux.sh [options] DISK                   erase DISK: EFI + NixOS
#   nixos/install-from-linux.sh [options] --free-space DISK      EFI + NixOS in DISK's free space
#   nixos/install-from-linux.sh [options] --shrink PART --keep N shrink ext4 PART to N GiB, use the rest
#   nixos/install-from-linux.sh [options] --delete P1,P2...      delete these partitions (same disk),
#                                                                keep the others, NixOS in the space freed
#   nixos/install-from-linux.sh [options] --boot-part P --root-part P   format these two only
#   nixos/install-from-linux.sh [options] --continue [--boot-part P --root-part P]
#                                                continue an existing install, nothing formatted: /etc/nixos
#                                                written again, build (reuses what is built), user setup
#   nixos/install-from-linux.sh --status         the progress of the install running in the background
#   After the confirmation, the install runs as a background service (in a terminal): closing
#   the terminal does not stop it. NIXOS_INSTALL_FOREGROUND=1 keeps it in the terminal.
#     --size N     NixOS partition size in GiB (--free-space / --shrink / --delete; default: all the space)
#     --wifi W     Wi-Fi networks saved here to copy to NixOS: active (default), all, none,
#                  or names separated by commas (the guided mode asks)
#     --ssh S      SSH keys / files from ~/.ssh to copy to NixOS: none (default), all, or
#                  names separated by commas, e.g. id_rsa,known_hosts (the guided mode asks)
#     --encrypt    NixOS partition as LUKS2 (passphrase at boot) + Btrfs subvolumes
#                  @ @home @nix @log, zstd compression (the guided mode asks)
#     --host       flake host (default: this machine's hostname if hosts/<it>.nix exists;
#                  required on a live CD)
#     --user       NixOS user (default: you; required on a live CD)
#     --timezone   e.g. Europe/Paris (default: this system's, America/Toronto on a live CD)
#   NIXOS_PASSWORD=...                   skip the password prompt
#   NIXOS_LUKS_PASSPHRASE=...            skip the disk passphrase prompt (--encrypt)
#   NIXOS_INSTALL_YES=1                  skip the typed confirmation
#   NIXOS_INSTALL_ALLOW_OS_DISK=/dev/X   let DISK mode erase X although it holds another OS
#   NIXOS_INSTALL_TEXT=1                 numbered prompts instead of the arrow-key menus
#
# Then reboot, pick "Limine" on that disk in the firmware boot menu (F8 / F11 / F12)
# and log in: the system and your home are complete, nothing else to run.
# Later, after a git pull: bash ~/nodestack/dotfiles/nixos/init.sh (updates)
# See nixos/docs/INSTALL.md.
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
# Catppuccin Macchiato (the desktop's theme) in terminals with 24-bit color; basic ANSI
# colors elsewhere (e.g. the Linux text console of a live CD)
if [[ -t 1 && $COLORTERM =~ ^(truecolor|24bit)$ ]]; then
    fg() { printf '\033[38;2;%sm' "$1"; } && bg() { printf '\033[48;2;%sm' "$1"; }
    B=$'\033[1m' R=$'\033[0m'
    DIM=$(fg "110;115;141") BLUE=$B$(fg "138;173;244") RED=$B$(fg "237;135;150") GREEN=$(fg "166;218;149")
    YELLOW=$B$(fg "238;212;159") MAUVE=$B$(fg "198;160;246")
    FRAME=$(fg "255;95;31") # box borders: WezTerm's split-line orange (#ff5f1f, terminal/wezterm/wezterm.lua)
    SEL=$B$(bg "138;173;244")$(fg "36;39;58")      # selected item: blue
    SEL_RED=$B$(bg "237;135;150")$(fg "36;39;58")  # selected item that can't be used: red
    SEL_YEL=$B$(bg "238;212;159")$(fg "36;39;58")  # selected item that destroys data: yellow
    unset -f fg bg
elif [[ -t 1 ]]; then
    B=$'\033[1m' R=$'\033[0m' DIM=$'\033[2m' BLUE=$'\033[1;34m' RED=$'\033[1;31m'
    YELLOW=$'\033[1;33m' GREEN=$'\033[32m' MAUVE=$'\033[1;35m' FRAME=$'\033[33m'
    SEL=$'\033[1;44;30m' SEL_RED=$'\033[1;41;30m' SEL_YEL=$'\033[1;43;30m'
else
    B="" DIM="" BLUE="" RED="" YELLOW="" GREEN="" MAUVE="" FRAME="" SEL="" SEL_RED="" SEL_YEL="" R=""
fi
STEP=0 STEPS=7
info() { printf '%s==>%s %s\n' "$BLUE" "$R" "$*"; }
step() {
    STEP=$((STEP + 1))
    # background install: a marker the progress view reads (lib/background.sh)
    [[ -z ${RUN_PLAN:-} ]] || printf '@@STEP %d %d %s %s\n' "$STEP" "$STEPS" "$(date +%s)" "$*"
    printf '\n%s[%d/%d]%s %s%s%s\n' "$BLUE" "$STEP" "$STEPS" "$R" "$B" "$*" "$R"
}
warn() { printf '%swarning:%s %s\n' "$YELLOW" "$R" "$*" >&2; }
die() {
    # leaving the menus: clear their screen first (only the main shell, not a $(...) check)
    if [[ -n ${TUI_SHOWN:-} && $BASHPID == "$$" ]]; then
        printf '\033[?25h\033[H\033[2J' >/dev/tty
        if [[ $* == cancelled ]]; then printf 'Cancelled: nothing has been changed on any disk.\n' && exit 1; fi
    fi
    printf '%serror:%s %s\n' "$RED" "$R" "$*" >&2
    exit 1
}
# box "title" "line" ...   (a rounded card like init.sh's, sized to the text; for the scrollback).
# "#Title" lines are section dividers; "Label     value" lines get the summary's colors.
box() {
    local title=$1 l w=0 pad t
    shift
    for l in "$title" "$@"; do ((${#l} > w)) && w=${#l}; done
    printf -v pad '%*s' $((w - ${#title})) ''
    printf '  %s╭─ %s%s%s%s ─%s╮%s\n' "$FRAME" "$R" "$MAUVE" "$title" "$R$FRAME" "${pad// /─}" "$R"
    for l in "$@"; do
        if [[ $l == "#"* ]]; then
            t=${l#\#}
            printf -v pad '%*s' $((w + 1 - ${#t})) ''
            printf '  %s├─ %s%s%s%s %s┤%s\n' "$FRAME" "$R" "$MAUVE" "$t" "$R$FRAME" "${pad// /─}" "$R"
            continue
        fi
        printf -v pad '%*s' $((w - ${#l})) ''
        line_style "$l"
        printf '  %s│%s %s%s%s%s%s%s%s   %s│%s\n' "$FRAME" "$R" "$LS" "${l:0:10}" "$R" "$RS" "${l:10}" "$R" "$pad" "$FRAME" "$R"
    done
    printf -v pad '%*s' $((w + 4)) ''
    printf '  %s╰%s╯%s\n' "$FRAME" "${pad// /─}" "$R"
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
# paint FRAME: draws a whole screen in one write over the previous one (cursor home, each line
# cleared to its end, the rest below cleared), so moving the cursor doesn't flicker
paint() { [[ -n ${IN_VIEW:-} ]] || TUI_SHOWN=1; printf '\033[H%s\033[K\033[J' "${1//$'\n'/$'\033[K\n'}" >/dev/tty; }
MENU_RED=()     # tags ui_menu shows in red: listed, but can't be used
MENU_DEFAULT="" # the tag ui_menu marks "(default)" (the pre-selected answer of a yes/no)
MENU_YELLOW=()  # tags ui_menu shows in yellow: a choice that destroys data (e.g. erase the disk)
ui_restore() { [[ $UI == tui ]] && printf '\033[?25h' >/dev/tty; return 0; }
trap ui_restore EXIT
# Cards like init.sh's: ╭─ Title ──╮ │ rows │ ╰──╯, CARD_W wide (terminal width, at most 104)
card_width() { CARD_W=$(($(tput cols 2>/dev/null || echo 80) - 4)) && ((CARD_W <= 104)) || CARD_W=104; ((CARD_W >= 40)) || CARD_W=40; }
rule() { local p && printf -v p '%*s' "$1" '' && printf '%s' "${p// /─}"; } # N -> ─ x N
card_top() { # COLOR TITLE [RIGHT]: top border with the title (and a dim note on the right)
    local col=$1 t=$2 rt=${3:-} n
    n=$((CARD_W - 5 - ${#t} - (${#rt} ? ${#rt} + 3 : 0)))
    ((n >= 1)) || n=1
    printf '  %s╭─ %s%s%s%s %s%s%s\n' "$col" "$R" "${MAUVE:-$B}" "$t" "$R$col" "$(rule "$n")" "${rt:+ $R$DIM$rt$R$col ─}" "╮$R"
}
card_bottom() { printf '  %s╰%s╯%s\n' "$1" "$(rule $((CARD_W - 2)))" "$R"; }
# line_style LINE -> LS (the label's color) RS (the rest's), for summary lines "Label     value":
# red = data destroyed, yellow = changed but kept, green = created / kept, blue = copied to NixOS
line_style() {
    if [[ $1 == "          "* ]]; then LS="" RS=$DIM && return 0; fi # a continuation line ("          -> ...")
    case ${1%% *} in
    ERASED | DELETED | Formatted) LS=$RED RS=$RED ;;
    Shrunk | Converted | Unmounted) LS=$YELLOW RS="" ;;
    New | Kept) LS=${GREEN:+$B$GREEN} RS="" ;;
    Untouched) LS=${GREEN:+$B$GREEN} RS=$DIM ;;
    Wi-Fi | SSH | Dotfiles) LS=$BLUE RS="" ;;
    Host | User | Timezone | Storage) LS=$MAUVE RS="" ;;
    *) LS="" RS="" ;; # not a summary line: as it is
    esac
}
# card_row COLOR TEXT [STYLE] [CONT] [LABEL]: TEXT wrapped inside the borders; STYLE colors the
# whole row (a selection fills its width); wrapped lines start with CONT (default: 4 spaces);
# LABEL colors the first 10 characters of the first line (summary labels)
card_row() {
    local col=$1 rest=$2 style=${3:-} cont=${4:-    } label=${5:-} inner=$((CARD_W - 4)) line chunk width pad
    width=$inner
    while true; do # wrap at the last space that fits (counts characters, not bytes)
        if ((${#rest} <= width)); then
            line=$rest rest=""
        else
            chunk=${rest:0:width}
            line=${chunk% *}
            [[ $chunk == *" "* && -n ${line// /} ]] || line=$chunk
            rest=${rest:${#line}} && rest=${rest#"${rest%%[! ]*}"}
        fi
        ((width == inner)) || line=$cont$line
        printf -v pad '%*s' $((inner - ${#line} > 0 ? inner - ${#line} : 0)) ''
        if [[ -n $label && $width == "$inner" ]]; then
            printf '  %s│%s %s%s%s%s%s%s%s %s│%s\n' "$col" "$R" "$label" "${line:0:10}" "$R" "$style" "${line:10}" "$pad" "$R" "$col" "$R"
        else
            printf '  %s│%s %s%s%s%s %s│%s\n' "$col" "$R" "$style" "$line" "$pad" "$R" "$col" "$R"
        fi
        [[ -n $rest ]] || break
        width=$((inner - ${#cont}))
    done
}
card_line() { # COLOR PLAIN STYLED: one row showing STYLED, padded by the width of PLAIN (same text, no colors)
    local pad
    printf -v pad '%*s' $((CARD_W - 4 - ${#2} > 0 ? CARD_W - 4 - ${#2} : 0)) ''
    printf '  %s│%s %s%s%s %s│%s\n' "$1" "$R" "$3" "$R" "$pad" "$1" "$R"
}
# A text line starting with WARN_MARK is a warning (a partition mounted right now, or one that is
# deleted): yellow. One starting with OK_MARK is kept as it is: green.
WARN_MARK=$'\x02' OK_MARK=$'\x03'
card_text() { # COLOR TEXT: a paragraph (blank lines kept)
    local col=$1 line
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line == "$WARN_MARK"* ]]; then card_row "$col" "${line#"$WARN_MARK"}" "$YELLOW" "  "
        elif [[ $line == "$OK_MARK"* ]]; then card_row "$col" "${line#"$OK_MARK"}" "${GREEN:+$B$GREEN}" "  "
        else card_row "$col" "$line" "" "  "; fi
    done <<<"$2"
}
plain_text() { # TEXT for the numbered mode / stderr: warning lines in yellow, kept ones in green
    local line
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line == "$WARN_MARK"* ]]; then printf '%s%s%s\n' "$YELLOW" "${line#"$WARN_MARK"}" "$R"
        elif [[ $line == "$OK_MARK"* ]]; then printf '%s%s%s\n' "${GREEN:+$B$GREEN}" "${line#"$OK_MARK"}" "$R"
        else printf '%s\n' "$line"; fi
    done <<<"$1"
}
mark_lines() { # MARK TEXT: every line of TEXT starts with MARK (instead of the one it had)
    local line
    while IFS= read -r line || [[ -n $line ]]; do printf '%s%s\n' "$1" "${line#"$WARN_MARK"}"; done <<<"$2"
}
summary_cards() { # the summary lines, one card per "#Title" section, colored per line
    local l open=""
    for l in "${lines[@]}"; do
        if [[ $l == "#"* ]]; then
            [[ -n $open ]] && card_bottom "$FRAME" && echo
            card_top "$FRAME" "${l#\#}" && open=1
        elif [[ -n $l ]]; then
            line_style "$l"
            card_row "$FRAME" "$l" "$RS" "          " "$LS"
        fi
    done
    [[ -z $open ]] || card_bottom "$FRAME"
}
screen() { # HEADING TEXT: clear, the header (what was picked so far), the heading's card
    local crumb="" col=$FRAME
    card_width
    ((${#CRUMBS[@]})) && crumb=$(printf '%s › ' "${CRUMBS[@]}") && crumb=${crumb% › }
    printf '\n  %s%s%s%s\n\n' "${MAUVE:-$B}" "$TITLE" "$R" "${crumb:+  $DIM·  $crumb$R}"
    [[ $1 == WARNING* || $1 == "Can't do that" ]] && col=$RED
    if [[ -n ${SCREEN_SUMMARY:-} ]]; then summary_cards && echo; fi # the summary's own cards first
    card_top "$col" "$1"
    if [[ -n $2 ]]; then card_text "$col" "$2"; else card_row "$col" ""; fi
    card_bottom "$col"
    echo
}
is_yellow() { local t; for t in ${MENU_YELLOW[@]+"${MENU_YELLOW[@]}"}; do [[ $t == "$1" ]] && return 0; done; return 1; }
is_red() { local t; for t in ${MENU_RED[@]+"${MENU_RED[@]}"}; do [[ $t == "$1" ]] && return 0; done; return 1; }
# Going back: every screen sets WENT_BACK when you press ← (h, Backspace on a menu; "<" in the
# numbered text mode) instead of answering. The steps below check it with went_back.
WENT_BACK=""
went_back() { [[ -n $WENT_BACK ]]; }
HINT_MENU="↑/↓ move   → / Enter select   ← back   q quit"
# read_key: one key from the terminal -> KEY (up down left right enter backspace esc, or the character)
read_key() {
    local k rest
    IFS= read -rsn1 k </dev/tty || die "cancelled"
    case $k in
    '') KEY=enter ;;
    $'\x7f' | $'\b') KEY=backspace ;;
    $'\033')
        IFS= read -rsn2 -t 0.05 rest </dev/tty || rest=""
        case $rest in
        '[A') KEY=up ;; '[B') KEY=down ;; '[C') KEY=right ;; '[D') KEY=left ;; '[H') KEY=home ;; '[F') KEY=end ;;
        '') KEY=esc ;;
        *) KEY="" && IFS= read -rsn4 -t 0.02 rest </dev/tty || true ;; # e.g. Delete (\033[3~): ignored
        esac
        ;;
    *) KEY=$k ;;
    esac
}
# ui_menu "heading" "text" tag item [tag item...]  -> REPLY (the tag of the picked item)
ui_menu() {
    local head=$1 text=$2 tags=() items=() i sel=0 key
    shift 2
    WENT_BACK=""
    (($#)) || die "nothing to choose from: $head"
    while (($#)); do tags+=("$1") items+=("$2") && shift 2; done
    if [[ $UI == text ]]; then
        printf '\n%s%s%s\n' "$B" "$head" "$R"
        [[ -n $text ]] && plain_text "$text"
        for i in "${!items[@]}"; do
            if is_red "${tags[$i]}"; then printf '  %s%2d) %s%s\n' "$RED" "$((i + 1))" "${items[$i]}" "$R"
            elif is_yellow "${tags[$i]}"; then printf '  %s%2d) %s%s\n' "$YELLOW" "$((i + 1))" "${items[$i]}" "$R"
            else printf '  %s%2d)%s %s%s\n' "$BLUE" "$((i + 1))" "$R" "${items[$i]}" "$([[ ${tags[$i]} == "$MENU_DEFAULT" ]] && echo "  $MAUVE(default)$R" || true)"; fi
        done
        while true; do
            read -rp "  number [1-${#items[@]}], < back: " key </dev/tty || die "cancelled"
            [[ $key == "<" ]] && WENT_BACK=1 && REPLY="" && return 0
            [[ $key =~ ^[0-9]+$ ]] && ((key >= 1 && key <= ${#items[@]})) && break
        done
        REPLY=${tags[$((key - 1))]}
        return 0
    fi
    printf '\033[?25l' >/dev/tty
    while true; do
        paint "$(
            screen "$head" "$text"
            card_top "$BLUE" "Choose" "$((sel + 1))/${#items[@]}"
            for i in "${!items[@]}"; do
                if is_red "${tags[$i]}"; then
                    if ((i == sel)); then card_row "$BLUE" "❯ ${items[$i]}" "$SEL_RED"; else card_row "$BLUE" "  ${items[$i]}" "$RED"; fi
                elif is_yellow "${tags[$i]}"; then
                    if ((i == sel)); then card_row "$BLUE" "❯ ${items[$i]}" "$SEL_YEL"; else card_row "$BLUE" "  ${items[$i]}" "$YELLOW"; fi
                elif [[ ${tags[$i]} == "$MENU_DEFAULT" ]]; then
                    if ((i == sel)); then card_row "$BLUE" "❯ ${items[$i]}  (default)" "$SEL"
                    else card_line "$BLUE" "  ${items[$i]}  (default)" "  ${items[$i]}  $MAUVE(default)"; fi
                elif ((i == sel)); then card_row "$BLUE" "❯ ${items[$i]}" "$SEL"; else card_row "$BLUE" "  ${items[$i]}"; fi
            done
            card_bottom "$BLUE"
            printf '   %s%s%s\n' "$DIM" "$HINT_MENU" "$R"
        )"
        read_key
        case $KEY in
        up | k) sel=$(((sel - 1 + ${#items[@]}) % ${#items[@]})) ;; # wraps: first -> last
        down | j) sel=$(((sel + 1) % ${#items[@]})) ;;              # wraps: last -> first
        home | g) sel=0 ;;
        end | G) sel=$((${#items[@]} - 1)) ;;
        [1-9]) ((KEY <= ${#items[@]})) && sel=$((KEY - 1)) ;;
        enter | right | l) break ;;
        left | h | backspace) WENT_BACK=1 && break ;;
        q | esc) printf '\033[?25h\n' >/dev/tty && die "cancelled" ;;
        esac
    done
    printf '\033[?25h' >/dev/tty
    REPLY=${tags[$sel]}
    [[ -z $WENT_BACK ]] || REPLY=""
    return 0
}
# ui_field HEADING TEXT DEFAULT [MASK] [PLACEHOLDER]: a one-line text field in a card (TUI).
# A DEFAULT is pre-filled in mauve: Enter keeps it, typing replaces it, Backspace edits it.
# A PLACEHOLDER (what an empty answer means, e.g. "all 38 GiB") shows in mauve while empty.
# Ctrl-U clears, Enter or → accepts, ← goes back, Esc quits. MASK=1 shows dots (passwords). -> REPLY
ui_field() {
    local head=$1 text=$2 buf=$3 mask=${4:-} ph=${5:-} shown i fresh=""
    [[ -n $buf ]] && fresh=1
    printf '\033[?25l' >/dev/tty
    while true; do
        shown=$buf
        if [[ -n $mask ]]; then shown="" && for ((i = 0; i < ${#buf}; i++)); do shown+="•"; done; fi
        paint "$(
            screen "$head" "$text"
            card_top "$BLUE" "$([[ -n $mask ]] && echo "Type (hidden)" || echo "Type")"
            if [[ -n $fresh ]]; then
                card_line "$BLUE" "> $shown▏  default: Enter keeps it, type to replace" "> $MAUVE$shown$R▏  ${DIM}default: Enter keeps it, type to replace"
            elif [[ -z $buf && -n $ph ]]; then
                card_line "$BLUE" "> ▏$ph  (default: Enter)" "> ▏$MAUVE$ph$R  ${DIM}(default: Enter)"
            else
                card_row "$BLUE" "> $shown▏"
            fi
            card_bottom "$BLUE"
            printf '   %s← back   → / Enter next   Backspace edit   Ctrl-U clear   Esc quit%s\n' "$DIM" "$R"
        )"
        read_key
        case $KEY in
        enter | right) break ;;
        left) WENT_BACK=1 && break ;;
        esc) printf '\033[?25h\n' >/dev/tty && die "cancelled" ;;
        backspace) buf=${buf%?} fresh="" ;;
        $'\x15') buf="" fresh="" ;; # Ctrl-U
        up | down | home | end | '') ;;
        *) if [[ $KEY == [[:print:]] ]]; then
            if [[ -n $fresh ]]; then buf=$KEY; else buf+=$KEY; fi
            fresh=""
        fi ;;
        esac
    done
    printf '\033[?25h' >/dev/tty
    REPLY=$buf
    [[ -z $WENT_BACK ]] || REPLY=""
    return 0
}
# ui_input "heading" "text" [default] [placeholder]  -> REPLY (see ui_field)
ui_input() {
    WENT_BACK=""
    if [[ $UI == tui ]]; then
        ui_field "$1" "$2" "${3:-}" "" "${4:-}"
    else
        printf '\n%s%s%s\n' "$B" "$1" "$R" && plain_text "$2"
        read -rp "  ${3:+[$MAUVE$3$R] }${4:+[$MAUVE$4$R] }(< back) > " REPLY </dev/tty || die "cancelled"
        [[ $REPLY == "<" ]] && WENT_BACK=1 && REPLY="" && return 0
        REPLY=${REPLY:-${3:-}}
    fi
    return 0
}
ui_password() { # "heading" "text" -> REPLY
    WENT_BACK=""
    if [[ $UI == tui ]]; then
        ui_field "$1" "$2" "" 1
    else
        read -rsp "  $2 (< back) " REPLY </dev/tty || die "cancelled"
        echo
        [[ $REPLY == "<" ]] && WENT_BACK=1 && REPLY=""
    fi
    return 0
}
# ui_yesno "heading" "text" [yes-label no-label]  -> status 0 for yes; the default is no.
# Status 1 for no, or for ← (then WENT_BACK is set: check went_back first)
ui_yesno() {
    local REPLY
    MENU_DEFAULT=no
    ui_menu "$1" "$2" no "${4:-No}" yes "${3:-Yes}"
    MENU_DEFAULT=""
    [[ $REPLY == yes ]]
}
ui_msg() {
    local rest
    if [[ $UI == tui ]]; then
        paint "$(screen "$1" "$2" && printf '   %spress a key%s' "$DIM" "$R")"
        read -rsn1 </dev/tty || true
        IFS= read -rsn5 -t 0.05 rest </dev/tty || true # the rest of an arrow key
    else
        printf '\n%s%s%s\n' "$B" "$1" "$R" && plain_text "$2"
    fi
}

# popup_yesno BASE TITLE TEXT YES-LABEL: a red box drawn under the screen BASE (TUI) asking
# yes / no; No is pre-selected. ←/→ (or Tab, h/l) switch, Enter picks, y / n answer, Esc = no.
# Status 0 for yes. Without the TUI: a [y/N] question.
popup_yesno() {
    local base=$1 title=$2 text=$3 yes=${4:-Yes} sel=0 no_b yes_b plain pad
    if [[ $UI == text ]]; then
        printf '%s%s%s\n' "$RED" "$text" "$R"
        read -rp "  $yes? [y/N] " REPLY </dev/tty || die "cancelled"
        [[ $REPLY =~ ^[yY] ]]
        return
    fi
    while true; do
        if ((sel == 0)); then no_b="$SEL [ No ] $R" yes_b="  $yes  "; else no_b="  No  " yes_b="$SEL_RED [ $yes ] $R"; fi
        plain="     No       $yes   " # the buttons' visible width, for the padding
        printf -v pad '%*s' $((CARD_W - 4 - ${#plain} > 0 ? CARD_W - 4 - ${#plain} : 0)) ''
        paint "$base
$(
            card_top "$RED" "$title"
            card_text "$RED" "$text"
            card_row "$RED" ""
            printf '  %s│%s   %s   %s%s %s│%s\n' "$RED" "$R" "$no_b" "$yes_b" "$pad" "$RED" "$R"
            card_bottom "$RED"
            printf '   %s←/→ choose   Enter confirm   y yes   n / Esc no%s\n' "$DIM" "$R"
        )"
        read_key
        case $KEY in
        left | right | h | l | $'\t') sel=$((1 - sel)) ;;
        y | Y) return 0 ;;
        n | N | esc) return 1 ;;
        enter) ((sel == 1)) && return 0 || return 1 ;;
        esac
    done
}

# ui_checklist "heading" "text" tag item on|off [...]  -> REPLY: the ticked tags, space-separated
# (tags must not contain spaces). Space ticks, a ticks all / none, Enter or → accepts, ← goes back.
# Tags in MENU_RED are shown in red; ticking one asks first (popup_yesno, the question from
# RED_WHY[tag]), and it stays unticked on "no".
declare -A RED_WHY=()
ui_checklist() {
    local head=$1 text=$2 tags=() items=() on=() i sel=0 key n frame
    shift 2
    WENT_BACK=""
    while (($#)); do tags+=("$1") items+=("$2") on+=("$3") && shift 3; done
    tick() { # INDEX BASE-FRAME: tick (asking first for a red one) or untick
        if [[ ${on[$1]} == on ]]; then on[$1]=off && return 0; fi
        if is_red "${tags[$1]}" && ! popup_yesno "$2" "In use" "${RED_WHY[${tags[$1]}]:-${tags[$1]} is in use.}" "Yes, delete it"; then return 0; fi
        on[$1]=on
    }
    if [[ $UI == text ]]; then
        while true; do
            printf '\n%s%s%s\n' "$B" "$head" "$R"
            [[ -n $text ]] && plain_text "$text"
            for i in "${!items[@]}"; do
                if is_red "${tags[$i]}"; then printf '  %s%2d) [%s] %s%s\n' "$RED" "$((i + 1))" "$([[ ${on[$i]} == on ]] && echo x || echo ' ')" "${items[$i]}" "$R"
                else printf '  %s%2d)%s [%s] %s\n' "$BLUE" "$((i + 1))" "$R" "$([[ ${on[$i]} == on ]] && echo x || echo ' ')" "${items[$i]}"; fi
            done
            read -rp "  numbers to tick / untick (e.g. 1,3), 'all', 'none', < back, Enter when done: " key </dev/tty || die "cancelled"
            [[ -z $key ]] && break
            case $key in
            "<") WENT_BACK=1 && REPLY="" && return 0 ;;
            all) for i in "${!on[@]}"; do [[ ${on[$i]} == on ]] || tick "$i" ""; done ;;
            none) for i in "${!on[@]}"; do on[$i]=off; done ;;
            *) for n in ${key//,/ }; do
                [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#items[@]})) || continue
                tick $((n - 1)) ""
            done ;;
            esac
        done
    else
        printf '\033[?25l' >/dev/tty
        while true; do
            frame=$(
                screen "$head" "$text"
                n=0 && for i in "${!on[@]}"; do [[ ${on[$i]} == on ]] && n=$((n + 1)); done
                card_top "$BLUE" "Pick" "$n/${#items[@]} ticked"
                for i in "${!items[@]}"; do
                    local box="○"
                    [[ ${on[$i]} == on ]] && box="●"
                    if ((i == sel)); then
                        if is_red "${tags[$i]}"; then card_row "$BLUE" "❯ $box ${items[$i]}" "$SEL_RED" "      "; else card_row "$BLUE" "❯ $box ${items[$i]}" "$SEL" "      "; fi
                    elif is_red "${tags[$i]}"; then card_row "$BLUE" "  $box ${items[$i]}" "$RED" "      "
                    elif [[ ${on[$i]} == on ]]; then card_row "$BLUE" "  $box ${items[$i]}" "$GREEN" "      "
                    else card_row "$BLUE" "  $box ${items[$i]}" "$DIM" "      "; fi
                done
                card_bottom "$BLUE"
            )
            card_width # paint's popup needs CARD_W outside the subshell too
            paint "$frame
   ${DIM}↑/↓ move   Space tick   a all/none   → / Enter accept   ← back   q quit$R"
            read_key
            case $KEY in
            up | k) sel=$(((sel - 1 + ${#items[@]}) % ${#items[@]})) ;; # wraps: first -> last
            down | j) sel=$(((sel + 1) % ${#items[@]})) ;;              # wraps: last -> first
            ' ') tick "$sel" "$frame" ;;
            a) if [[ " ${on[*]} " == *" off "* ]]; then for i in "${!on[@]}"; do [[ ${on[$i]} == on ]] || tick "$i" "$frame"; done
               else for i in "${!on[@]}"; do on[$i]=off; done; fi ;;
            enter | right | l) break ;;
            left | h | backspace) WENT_BACK=1 && break ;;
            q | esc) printf '\033[?25h\n' >/dev/tty && die "cancelled" ;;
            esac
        done
        printf '\033[?25h' >/dev/tty
        if went_back; then REPLY="" && return 0; fi
    fi
    REPLY=""
    for i in "${!tags[@]}"; do [[ ${on[$i]} == on ]] && REPLY+="${tags[$i]} "; done
    REPLY=${REPLY% }
    return 0
}

# --- arguments ----------------------------------------------------------------------
HOST="" USERNAME="" TIMEZONE="" DISK="" BOOT_PART="" ROOT_PART=""
FREE_DISK="" SHRINK_PART="" SHRINK_GIB="" NIXOS_GIB="" WIFI_ARG="" SSH_ARG="" ENCRYPT="" DELETE_ARG=""
LUKS_NAME=cryptroot LUKS_LABEL=nixos-crypt STATUS="" RUN_PLAN="" RESUME_ARG=""
while (($#)); do
    case $1 in
    --status) STATUS=1 && shift ;;
    --continue) RESUME_ARG=1 && shift ;;
    --run-plan) RUN_PLAN=$2 && shift 2 ;; # the background service (lib/background.sh), not for you
    --host) HOST=$2 && shift 2 ;;
    --user) USERNAME=$2 && shift 2 ;;
    --timezone) TIMEZONE=$2 && shift 2 ;;
    --boot-part) BOOT_PART=$2 && shift 2 ;;
    --root-part) ROOT_PART=$2 && shift 2 ;;
    --free-space) FREE_DISK=$2 && shift 2 ;;
    --shrink) SHRINK_PART=$2 && shift 2 ;;
    --keep) SHRINK_GIB=$2 && shift 2 ;;
    --delete) DELETE_ARG=$2 && shift 2 ;;
    --size) NIXOS_GIB=$2 && shift 2 ;;
    --wifi) WIFI_ARG=$2 && shift 2 ;;
    --ssh) SSH_ARG=$2 && shift 2 ;;
    --encrypt) ENCRYPT=1 && shift ;;
    -h | --help) sed -n '3,41p' "$0" | sed 's/^# \{0,1\}//' && exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) DISK=$1 && shift ;;
    esac
done

# shellcheck source=lib/background.sh
. "$NIXOS_DIR/lib/background.sh"
if [[ -z $RUN_PLAN ]]; then
    if [[ -n $STATUS ]]; then bg_status; exit $?; fi
    if bg_running; then # one install at a time: show the one that runs
        info "An install is running in the background: showing its progress"
        bg_status
        exit $?
    fi
fi
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
[[ -n $DELETE_ARG ]] && modes=$((modes + 1))
((modes <= 1)) || die "pick one of: DISK, --free-space, --shrink, --delete, --boot-part/--root-part"
if [[ -n $BOOT_PART || -n $ROOT_PART ]]; then
    [[ -n $BOOT_PART && -n $ROOT_PART ]] || die "--boot-part and --root-part go together"
fi
[[ -z $SHRINK_PART || $SHRINK_GIB =~ ^[0-9]+$ ]] || die "--shrink needs --keep N (GiB to keep for $SHRINK_PART)"
[[ -z $NIXOS_GIB || $NIXOS_GIB =~ ^[0-9]+$ ]] || die "--size takes a whole number of GiB"
[[ -z $RESUME_ARG || ( -z $DISK && -z $FREE_DISK && -z $SHRINK_PART && -z $DELETE_ARG ) ]] ||
    die "--continue continues an existing install: only --boot-part / --root-part go with it"
GUIDED=""
if ((modes == 0)) && [[ -z $RUN_PLAN && -z $RESUME_ARG ]]; then
    [[ -t 0 ]] || die "which disk? e.g. $0 /dev/nvme1n1, or run it in a terminal to choose (see: lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS)"
    GUIDED=1
fi

# A live CD: / is in RAM, and its hostname ("nixos", "ubuntu") and user mean nothing.
LIVE=""
if grep -q '^VARIANT_ID=installer' /etc/os-release 2>/dev/null ||
    [[ $(findmnt -no FSTYPE / 2>/dev/null) =~ ^(overlay|tmpfs|squashfs|aufs|rootfs)$ ]] ||
    [[ -d /cdrom/casper || -d /run/initramfs/live || -d /iso ]]; then
    LIVE=1
else
    [[ $EUID -ne 0 || -n $RUN_PLAN ]] || die "run as your user (it uses sudo where needed)"
fi
[[ -n $LIVE && -z $GUIDED ]] && info "Live system detected: the host and user are not guessed"
# The running OS's name, as it calls itself ("Pop!_OS 24.04 LTS", "Ubuntu 24.04.1 LTS", ...)
RUNNING_OS=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-}}")
RUNNING_OS=${RUNNING_OS:-this Linux}
[[ -z $LIVE ]] || RUNNING_OS="the live system ($RUNNING_OS)"

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
# own NIXBOOT, so re-installing works), or LUKS / LVM / Windows / ZFS partitions (except
# NixOS's own LUKS partition, labelled nixos-crypt by --encrypt).
# Needs no mounting, so it also finds an installed OS from a live CD, where nothing of it is mounted.
os_part_problem() { # PARTITION -> why it belongs to another OS ("is ..."), or nothing
    local p=$1 fstype entry
    fstype=$(lsblk -dno FSTYPE "$p")
    [[ $fstype == crypto_LUKS && $(lsblk -dno LABEL "$p") == "$LUKS_LABEL" ]] && return 0
    case $fstype in
    crypto_LUKS | LVM2_member | ntfs | BitLocker | zfs_member) echo "is $fstype (another OS or encrypted data)" && return 0 ;;
    esac
    [[ $(lsblk -dno LABEL "$p") == NIXBOOT ]] && return 0
    entry=$(boot_entry_of "$p")
    [[ -z $entry ]] || echo "is the boot partition of \"$entry\""
    return 0
}
os_problem() { # DISK -> reason, or nothing
    local d=$1 p why
    while read -r p; do
        why=$(os_part_problem "$p")
        [[ -z $why ]] && continue
        if [[ $why == *"boot partition"* ]]; then echo "$d holds another OS: $p $why"; else echo "$d holds another OS or encrypted data: $p ${why% (*}"; fi
        return 0
    done < <(parts_of "$d")
    return 0
}
# free_after_delete DISK "P1 P2...": the largest free region once those partitions are gone
# -> "START END SECTORS" (logical sectors; the disk's first MiB and GPT's last 33 sectors excluded)
free_after_delete() {
    local d=$1 del=" $2 " p s e cur best_s=0 best_e=-1 last ss
    ss=$(sector_size "$d")
    last=$(($(blockdev --getsz "$d" 2>/dev/null || sudo blockdev --getsz "$d") * 512 / ss - 34))
    cur=$((1048576 / ss))
    while read -r p s e; do
        [[ $del == *" $p "* ]] && continue
        if ((s - 1 - cur > best_e - best_s)); then best_s=$cur best_e=$((s - 1)); fi
        ((e + 1 > cur)) && cur=$((e + 1))
    done < <(for p in $(parts_of "$d"); do # sysfs counts 512-byte units, whatever the sector size
        s=$(($(cat "/sys/class/block/$(basename "$p")/start") * 512 / ss))
        printf '%s %s %s\n' "$p" "$s" "$((s + $(cat "/sys/class/block/$(basename "$p")/size") * 512 / ss - 1))"
    done | sort -k2,2n)
    if ((last - cur > best_e - best_s)); then best_s=$cur best_e=$last; fi
    echo "$best_s $best_e $((best_e - best_s + 1))"
}
is_sys_disk() { grep -qxF "$1" <<<"$SYS_DISKS"; }
mounted_in() { lsblk -nro MOUNTPOINTS "$1" | grep -v '^$' | sort -u | paste -sd' ' - || true; } # DEV -> "mp mp" (or nothing)
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
    if [[ $d == "$disk" ]]; then # a whole disk: no filesystem or label columns
        printf '%-8s %7s  %s' "$(basename "$d")" "$(lsblk -dno SIZE "$d" | tr -d ' ')" "${model:-}"
        return 0
    fi
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
        # a mounted partition is in use right now: marked as a warning (yellow)
        printf '%s  %s%s%s\n' "${mp:+$WARN_MARK}" "$(describe "$p" | sed 's/ *(.*)$//')" "${mp:+  mounted on $mp${used:+, $used used}}" "${entry:+  <- boot entry \"$entry\"}"
    done < <(parts_of "$1")
}

# --- the questions, as steps you can go back through ---------------------------------------------
# Each step asks one thing (or works it out from the arguments). The driver at the end runs them in
# order: ← on a screen goes back one step, steps with nothing to ask are passed over both ways, and
# ← on the first screen asks whether to quit. Nothing is written to any disk before the last
# step (the typed confirmation); after it the install runs without questions.
HOSTS=$(sed -n 's/^ *\([A-Za-z0-9_-]*\) *= *mkHost "\([^"]*\)".*/\1 \2/p' "$NIXOS_DIR/flake.nix")
HOST_ARG=$HOST USERNAME_ARG=$USERNAME TIMEZONE_ARG=$TIMEZONE ENCRYPT_ARG=$ENCRYPT SIZE_ARG=$NIXOS_GIB
DELETE_PARTS=() # --delete / the "delete" layout: partitions to delete
MODE="" OS_REASON="" NEED_GPT="" RELEASE=() FREE_START="" FREE_END="" BOOT_DEV="" ROOT_DEV=""
host_system="" PASSWORD="" LUKS_PASS="" CONFIRM="" lines=() STALE_UUIDS=()
SKIPPED="" STEP_CRUMB=""
skip() { SKIPPED=1; } # this step has nothing to ask (now): the driver moves on in the same direction

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

step_host() {
    local items=() h s
    HOST=$HOST_ARG
    if [[ -z $HOST ]]; then
        if [[ -z $LIVE && -f "$NIXOS_DIR/hosts/$(hostname).nix" ]] && grep -q "^$(hostname) " <<<"$HOSTS"; then
            HOST=$(hostname)
        elif [[ -n $GUIDED ]]; then
            while read -r h s; do
                [[ $s == "$(uname -m)-linux" ]] && items+=("$h" "$h  ($s, hosts/$h.nix)")
            done <<<"$HOSTS"
            ui_menu "Host" "Which host from nixos/flake.nix?${LIVE:+ (live system: the hostname is not used)}" "${items[@]}"
            if went_back; then return 0; fi
            HOST=$REPLY
        else
            die "pass --host (one of: $(awk '{ printf "%s ", $1 }' <<<"$HOSTS"))"
        fi
    fi
    host_system=$(awk -v h="$HOST" '$1 == h { print $2 }' <<<"$HOSTS")
    [[ -n $host_system ]] || die "host '$HOST' is not in nixos/flake.nix"
    [[ $host_system == "$(uname -m)-linux" ]] || die "host '$HOST' is $host_system, this machine is $(uname -m)"
    STEP_CRUMB="host $HOST"
    ((${#items[@]})) || skip # nothing was asked
    return 0
}

step_disk() { # guided: every disk is listed; the ones NixOS can't go on say why, and can't be picked
    local items=() blocked=() usable=0 d why os tag
    [[ -n $GUIDED ]] || { skip && return 0; }
    while read -r d; do
        why=$(disk_ok "$d" mounted)
        if [[ -n $why ]]; then
            [[ $why == *"running system"* ]] && why="IN USE: $RUNNING_OS runs from it"
            items+=("$d" "$(describe "$d")  [${why#"$d is "}, can't be used]") blocked+=("$d")
            continue
        fi
        usable=$((usable + 1))
        os=$(os_problem "$d")
        tag="empty"
        [[ -n $(parts_of "$d") ]] && tag="data: $(parts_of "$d" | while read -r p; do printf '%s ' "$(lsblk -dno FSTYPE "$p")"; done | sed 's/ *$//')"
        [[ -n $(mounted_in "$d") ]] && tag+=", mounted on $(mounted_in "$d")"
        [[ -n $os ]] && tag="ANOTHER OS: ${os#*: }"
        items+=("$d" "$(describe "$d")  [$tag]")
    done < <(lsblk -dnpo NAME,TYPE | awk -v loop="${NIXOS_INSTALL_ALLOW_LOOP:+loop}" '($2 == "disk" || $2 == loop) && $1 !~ /^\/dev\/(zram|ram)/ { print $1 }')
    ((usable)) || die "no disk available: $(printf '%s ' "${blocked[@]}")can't be used (the running system's, or not whole disks)"
    MENU_RED=(${blocked[@]+"${blocked[@]}"})
    while true; do
        ui_menu "Disk" "Which disk should NixOS go on?" "${items[@]}"
        if went_back; then MENU_RED=() && return 0; fi
        DISK=$REPLY
        printf '%s\n' "${blocked[@]}" | grep -qxF "$DISK" || break
        why=$(disk_ok "$DISK" mounted)
        [[ $why == *"running system"* ]] && why="$DISK can't be used: $RUNNING_OS runs from it."
        ui_msg "Disk" "$why
Nothing is written to it. Pick another disk (on a live USB, every internal disk can be picked)."
    done
    MENU_RED=()
    OS_REASON=$(os_problem "$DISK")
    STEP_CRUMB=$(basename "$DISK")
    return 0
}

# existing_nixos DISK: a NixOS this installer made (NIXBOOT EFI partition + nixos / nixos-crypt
# root) -> EX_BOOT EX_ROOT EX_ENC (1 when the root is LUKS), status 1 when there is none
existing_nixos() {
    local p
    EX_BOOT="" EX_ROOT="" EX_ENC=""
    for p in $(parts_of "$1"); do
        if [[ $(lsblk -dno LABEL "$p") == NIXBOOT && $(lsblk -dno PARTTYPE "$p") == "$EFI_TYPE" ]]; then EX_BOOT=$p
        elif [[ $(lsblk -dno FSTYPE "$p") == crypto_LUKS && $(lsblk -dno LABEL "$p") == "$LUKS_LABEL" ]]; then EX_ROOT=$p EX_ENC=1
        elif [[ $(lsblk -dno FSTYPE "$p") =~ ^(ext4|btrfs)$ && $(lsblk -dno LABEL "$p") == nixos ]]; then EX_ROOT=$p; fi
    done
    [[ -n $EX_BOOT && -n $EX_ROOT ]]
}
step_existing() { # guided: this disk already has NixOS on it: continue that install, or a new one
    local enc
    if [[ -z $GUIDED ]] || ! existing_nixos "$DISK"; then MODE="" && skip && return 0; fi
    enc=$([[ -n $EX_ENC ]] && echo ", encrypted" || true)
    MENU_DEFAULT="continue"
    ui_menu "Existing NixOS" "$(describe "$DISK")"$'\n\n'"$(contents "$DISK")

NixOS is already installed here: $(basename "$EX_BOOT") (EFI) + $(basename "$EX_ROOT") (NixOS$enc).
Continue: nothing is formatted, its data stays. /etc/nixos is written again from this checkout,
the system is built (what is already built is reused) and the home set up again." \
        continue "Continue this install (config, build, home setup)" \
        new "New install on this disk (pick a layout: delete partitions, erase...)"
    MENU_DEFAULT=""
    if went_back; then return 0; fi
    if [[ $REPLY == new ]]; then MODE="" && return 0; fi
    MODE=resume BOOT_DEV=$EX_BOOT ROOT_DEV=$EX_ROOT ENCRYPT=$EX_ENC
    STEP_CRUMB="continue"
    return 0
}

step_layout() { # guided: what this disk allows
    local items text r secs p
    [[ -n $GUIDED && $MODE != resume ]] || { skip && return 0; }
    items=()
    # First: pick what to delete and what to keep (also on a disk with another OS: delete its partitions)
    [[ -n $(parts_of "$DISK") && -z $(gpt_or_convertible "$DISK") ]] &&
        items+=(delete "Delete some partitions, keep the others: NixOS in the space freed")
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
    fi
    # Last, in yellow: everything on the disk is destroyed. (Two existing partitions: --boot-part / --root-part)
    items+=(erase "Erase the whole disk: 1 GiB EFI + NixOS on the rest")
    text="$(describe "$DISK")"$'\n\n'"$(contents "$DISK")"
    [[ -n $OS_REASON ]] && text+=$'\n\n'"It holds another OS: NixOS only goes in its place (erase the disk, or delete that OS's partitions)."
    if [[ -n $ENCRYPT_ARG ]]; then
        text+=$'\n\n'"Encryption: on (--encrypt), the NixOS partition will be LUKS2 + Btrfs."
    else
        text+=$'\n\n'"Encryption (LUKS2) is the next question, for any of these layouts."
    fi
    MENU_YELLOW=(erase)
    ui_menu "Layout" "$text" "${items[@]}"
    MENU_YELLOW=()
    if went_back; then return 0; fi
    MODE=$REPLY
    STEP_CRUMB=$MODE
    return 0
}

step_encrypt() { # guided, right after the layout (any layout can be encrypted)
    if [[ $MODE == resume ]]; then skip && return 0; fi # an existing install: it is (or not) already
    ENCRYPT=$ENCRYPT_ARG
    if [[ -z $GUIDED || -n $ENCRYPT_ARG ]]; then
        [[ -n $ENCRYPT ]] && STEP_CRUMB="encrypted"
        skip && return 0
    fi
    MENU_DEFAULT=encrypt
    ui_menu "Encryption" "Encrypt NixOS's partition?

Encrypt: LUKS2 with Btrfs inside (subvolumes @ @home @nix @log, zstd compression).
  - Without the passphrase the data can't be read: not from a live USB, not from
    another computer. If the passphrase is lost, the data is gone.
  - Every boot: the passphrase on the boot splash, then the Caelestia lock as today
    (two passwords). The boot prompt uses the US keyboard layout.
  - Secure Boot and TPM unlock are not set up (later, see nixos/docs/ENCRYPTION.md).
No encryption: plain ext4.

The EFI partition stays unencrypted (it only holds the boot loader and kernels)." \
        encrypt "Encrypt (LUKS2 + Btrfs)" plain "No encryption (ext4)"
    MENU_DEFAULT=""
    if went_back; then return 0; fi
    [[ $REPLY == encrypt ]] && ENCRYPT=1 STEP_CRUMB="encrypted"
    return 0
}

step_details() { # guided: the size, or which partition(s); a small step list of its own, ← included
    local items=() p ss avail lo hi sub=0
    [[ -n $GUIDED && $MODE != resume ]] || { skip && return 0; }
    NIXOS_GIB=$SIZE_ARG SHRINK_PART="" SHRINK_GIB="" BOOT_PART="" ROOT_PART="" DELETE_PARTS=()
    case $MODE in
    erase) skip ;;
    delete)
        local why mp region keep_os ticked=" "
        while true; do
            if ((sub == 0)); then
                items=() MENU_RED=() RED_WHY=() # rebuilt each time: what you ticked stays ticked after a message
                for p in $(parts_of "$DISK"); do
                    why=$(os_part_problem "$p") mp=$(mounted_in "$p")
                    items+=("$p" "$(describe "$p")${mp:+  [mounted on $mp]}${why:+  [another OS: ${why#is }]}" "$([[ $ticked == *" $p "* ]] && echo on || echo off)")
                    if [[ -n $mp ]]; then # in use here: red, and ticking it asks first
                        MENU_RED+=("$p")
                        RED_WHY[$p]="$(basename "$p") is mounted on $mp ($(df -h --output=used "$p" 2>/dev/null | tail -1 | tr -d ' ') used): this system is using it right now.
Delete it anyway? It is unmounted before it is deleted, and all its data is lost."
                    fi
                done
                ui_checklist "Delete" "Tick the partitions to DELETE (their data is destroyed). Unticked ones are kept as they are.
NixOS goes in the largest free space that is left (it needs $((MIN_NIXOS_GIB + 1)) GiB)." "${items[@]}"
                MENU_RED=()
                if went_back; then return 0; fi
                read -ra DELETE_PARTS <<<"$REPLY"
                ticked=" $REPLY "
                if ((${#DELETE_PARTS[@]} == 0)); then ui_msg "Delete" "Nothing ticked: tick at least one partition, or go back (←) and pick another layout." && continue; fi
                keep_os=""
                for p in $(parts_of "$DISK"); do
                    [[ " $REPLY " == *" $p "* ]] && continue
                    why=$(os_part_problem "$p")
                    [[ -n $why ]] && keep_os+="  $(basename "$p") $why"$'\n'
                done
                if [[ -n $keep_os ]]; then
                    ui_msg "Delete" "These would stay, and they belong to another OS:
$keep_os
NixOS doesn't go next to another OS on the same disk: tick them too, or pick another layout."
                    continue
                fi
                region=$(free_after_delete "$DISK" "$REPLY")
                read -r FREE_START FREE_END _ <<<"$region"
                ss=$(sector_size "$DISK")
                avail=$((((FREE_END - FREE_START + 1) * ss - GiB) / GiB))
                if ((avail < MIN_NIXOS_GIB)); then
                    ui_msg "Delete" "That frees at most $(gib $(((FREE_END - FREE_START + 1) * ss))) GiB in one piece; NixOS needs $((MIN_NIXOS_GIB + 1)). Tick more, or neighbouring partitions."
                    continue
                fi
                sub=1
            else
                ui_input "NixOS size" "The largest free space after deleting is $((avail + 1)) GiB.
Size of the NixOS partition in GiB ($MIN_NIXOS_GIB to $avail):" "" "all $avail GiB"
                if went_back; then WENT_BACK="" sub=0 && continue; fi
                [[ -z $REPLY ]] && NIXOS_GIB="" && break
                [[ $REPLY =~ ^[0-9]+$ ]] && ((REPLY >= MIN_NIXOS_GIB && REPLY <= avail)) && NIXOS_GIB=$REPLY && break
            fi
        done
        ;;
    free)
        plan_free "$DISK"
        ss=$(sector_size "$DISK")
        avail=$((((FREE_END - FREE_START + 1) * ss - GiB) / GiB))
        while true; do
            ui_input "NixOS size" "Size of the NixOS partition in GiB ($MIN_NIXOS_GIB to $avail):" "" "all $avail GiB"
            if went_back; then return 0; fi
            [[ -z $REPLY ]] && NIXOS_GIB="" && break
            [[ $REPLY =~ ^[0-9]+$ ]] && ((REPLY >= MIN_NIXOS_GIB && REPLY <= avail)) && NIXOS_GIB=$REPLY && break
        done
        ;;
    shrink)
        for p in $(parts_of "$DISK"); do
            [[ $(lsblk -dno FSTYPE "$p") == ext4 ]] || continue
            shrink_limits "$p"
            ((SH_SIZE - SH_MIN >= (MIN_NIXOS_GIB + 1) * GiB)) || continue
            items+=("$p" "$(describe "$p")  [$(gib "$SH_USED") GiB used, can free up to $(gib $((SH_SIZE - SH_MIN))) GiB]")
        done
        ((${#items[@]})) || die "no ext4 partition on $DISK can free the $((MIN_NIXOS_GIB + 1)) GiB NixOS needs"
        while true; do
            if ((sub == 0)); then
                ui_menu "Shrink" "Which partition should give space to NixOS? Its data is kept." "${items[@]}"
                if went_back; then return 0; fi
                SHRINK_PART=$REPLY sub=1
            else
                shrink_limits "$SHRINK_PART"
                lo=$(((SH_MIN + GiB - 1) / GiB)) hi=$(((SH_SIZE - (MIN_NIXOS_GIB + 1) * GiB) / GiB))
                ui_input "Shrink $(basename "$SHRINK_PART")" "$(basename "$SHRINK_PART") is $(gib "$SH_SIZE") GiB with $(gib "$SH_USED") GiB used.
How many GiB should it keep? ($lo to $hi; NixOS gets the rest)" "${SHRINK_GIB:-$(((lo + hi) / 2))}"
                if went_back; then WENT_BACK="" sub=0 && continue; fi
                [[ $REPLY =~ ^[0-9]+$ ]] && ((REPLY >= lo && REPLY <= hi)) && SHRINK_GIB=$REPLY && break
            fi
        done
        ;;
    esac
    return 0
}

step_plan_args() { # not guided: the layout comes from the arguments
    local d found=()
    if [[ -n $RESUME_ARG ]]; then # --continue: an existing install, given or found by its labels
        MODE=resume
        if [[ -n $ROOT_PART ]]; then
            BOOT_DEV=$BOOT_PART ROOT_DEV=$ROOT_PART DISK=/dev/$(lsblk -dno PKNAME "$ROOT_PART" 2>/dev/null || true)
            ENCRYPT=$([[ $(lsblk -dno FSTYPE "$ROOT_PART") == crypto_LUKS ]] && echo 1 || true)
        else
            for d in $(lsblk -dnpo NAME,TYPE | awk -v loop="${NIXOS_INSTALL_ALLOW_LOOP:+loop}" '$2 == "disk" || $2 == loop { print $1 }'); do
                is_sys_disk "$d" && continue
                existing_nixos "$d" && found+=("$d")
            done
            ((${#found[@]} == 1)) || die "--continue: $([[ ${#found[@]} == 0 ]] && echo "no existing NixOS install found (NIXBOOT + nixos / nixos-crypt partitions)" || echo "several NixOS installs (${found[*]})"): pass --boot-part and --root-part"
            existing_nixos "${found[0]}"
            DISK=${found[0]} BOOT_DEV=$EX_BOOT ROOT_DEV=$EX_ROOT ENCRYPT=$EX_ENC
        fi
        skip && return 0
    fi
    if [[ -z $GUIDED ]]; then
        if [[ -n $DISK ]]; then
            MODE=erase
        elif [[ -n $FREE_DISK ]]; then
            MODE=free DISK=$FREE_DISK
        elif [[ -n $SHRINK_PART ]]; then
            MODE=shrink DISK=/dev/$(lsblk -dno PKNAME "$SHRINK_PART" 2>/dev/null || true)
        elif [[ -n $DELETE_ARG ]]; then
            IFS=, read -ra DELETE_PARTS <<<"$DELETE_ARG"
            MODE=delete DISK=/dev/$(lsblk -dno PKNAME "${DELETE_PARTS[0]}" 2>/dev/null || true)
        else
            MODE=parts DISK=/dev/$(lsblk -dno PKNAME "$ROOT_PART" 2>/dev/null || true)
        fi
    fi
    skip
    return 0
}

validate_plan() { # guided or not, the same checks; dies with the reason
    local problem p
    RELEASE=() NEED_GPT=""
    [[ $MODE == resume ]] || BOOT_DEV="" ROOT_DEV="" # set by the layout's steps (resume: found already)
    [[ $DISK != /dev/ ]] || die "not a partition: ${SHRINK_PART:-${ROOT_PART:-${DELETE_PARTS[0]:-}}}"
    OS_REASON=$(os_problem "$DISK")
    case $MODE in
    resume)
        problem=$(disk_ok "$DISK" mounted)
        [[ -z $problem ]] || die "$problem"
        for p in "$BOOT_DEV" "$ROOT_DEV"; do
            [[ -b $p && $(lsblk -dno TYPE "$p") == part ]] || die "$p is not a partition"
            [[ /dev/$(lsblk -dno PKNAME "$p") == "$DISK" ]] || die "--boot-part and --root-part must be on the same disk"
            [[ -z $(mounted_in "$p") ]] || die "$p is in use (mounted on $(mounted_in "$p")): unmount it first"
        done
        [[ $(lsblk -dno PARTTYPE "$BOOT_DEV") == "$EFI_TYPE" && $(lsblk -dno FSTYPE "$BOOT_DEV") == vfat ]] || die "$BOOT_DEV is not an EFI (vfat) partition"
        [[ $(lsblk -dno FSTYPE "$ROOT_DEV") =~ ^(crypto_LUKS|ext4|btrfs)$ ]] || die "$ROOT_DEV is not a NixOS partition (LUKS, ext4 or Btrfs)"
        [[ ! -e /dev/mapper/$LUKS_NAME ]] || die "/dev/mapper/$LUKS_NAME is already open: close it first (sudo cryptsetup close $LUKS_NAME)"
        ;;
    erase)
        problem=$(disk_ok "$DISK" ${GUIDED:+mounted})
        [[ -z $problem ]] || die "$problem"
        if [[ -n $OS_REASON && -z $GUIDED && ${NIXOS_INSTALL_ALLOW_OS_DISK:-} != "$DISK" ]]; then
            die "$OS_REASON. To erase it anyway: NIXOS_INSTALL_ALLOW_OS_DISK=$DISK"
        fi
        ;;
    delete)
        problem=$(disk_ok "$DISK" mounted)
        [[ -z $problem ]] || die "$problem"
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
        [[ $(lsblk -dno PTTYPE "$DISK") == gpt ]] || die "$DISK is not GPT (the UEFI boot loader needs a GPT EFI partition)"
        [[ $(lsblk -dno PARTTYPE "$BOOT_PART") == "$EFI_TYPE" ]] || die "$BOOT_PART is not an EFI system partition (GPT type EF00)"
        BOOT_DEV=$BOOT_PART ROOT_DEV=$ROOT_PART
        ;;
    erase)
        for p in $(parts_of "$DISK"); do [[ -n $(mounted_in "$p") ]] && RELEASE+=("$p"); done
        ;;
    delete)
        local keep r ss
        ((${#DELETE_PARTS[@]})) || die "--delete: no partition given"
        for p in "${DELETE_PARTS[@]}"; do
            [[ -b $p && $(lsblk -dno TYPE "$p") == part ]] || die "$p is not a partition"
            [[ /dev/$(lsblk -dno PKNAME "$p") == "$DISK" ]] || die "--delete: the partitions must all be on the same disk ($p is not on $DISK)"
            [[ -n $(mounted_in "$p") ]] && RELEASE+=("$p")
        done
        for p in $(parts_of "$DISK"); do
            [[ " ${DELETE_PARTS[*]} " == *" $p "* ]] && continue
            keep=$(os_part_problem "$p")
            [[ -z $keep ]] || die "$p $keep and would be kept: NixOS doesn't go next to another OS on the same disk; delete it too, or erase the disk"
        done
        gpt_check "$DISK"
        [[ -z $GPT_PROBLEM ]] || die "$GPT_PROBLEM"
        r=$(free_after_delete "$DISK" "${DELETE_PARTS[*]}")
        read -r FREE_START FREE_END _ <<<"$r"
        ss=$(sector_size "$DISK")
        (((FREE_END - FREE_START + 1) * ss >= (MIN_NIXOS_GIB + 1) * GiB)) ||
            die "deleting ${DELETE_PARTS[*]} frees at most $(gib $(((FREE_END - FREE_START + 1) * ss))) GiB in one piece; NixOS needs $((MIN_NIXOS_GIB + 1))"
        [[ -z $NIXOS_GIB ]] || (((FREE_END - FREE_START + 1) * ss >= (NIXOS_GIB + 1) * GiB)) || die "--size $NIXOS_GIB does not fit in the space freed"
        ;;
    esac
    # Things mounted on volumes inside a partition (LUKS / LVM) can't be released safely here
    for p in ${RELEASE[@]+"${RELEASE[@]}"}; do
        [[ -z $(lsblk -nro NAME "$p" | tail -n +2) ]] || die "$p has open LUKS / LVM volumes on it: close them first"
    done
    return 0
}
step_validate() { # guided: a plan that fails a check is shown, and you go back to change it
    local err
    if [[ -n $GUIDED ]] && ! err=$(validate_plan 2>&1 >/dev/null); then
        ui_msg "Can't do that" "$(sed 's/\x1b\[[0-9;]*m//g; s/^error: //' <<<"$err")

Nothing has been changed. Go back and pick something else."
        WENT_BACK=1
        return 0
    fi
    validate_plan
    skip
    return 0
}

step_user() {
    USERNAME=$USERNAME_ARG
    if [[ -n $USERNAME ]]; then skip && return 0; fi
    if [[ -z $LIVE ]]; then USERNAME=$(id -un) && skip && return 0; fi
    [[ -n $GUIDED ]] || die "on a live CD, pass --user NAME"
    while [[ ! $USERNAME =~ ^[a-z_][a-z0-9._-]*$ ]]; do
        ui_input "User" "NixOS user name (lowercase):" ""
        if went_back; then return 0; fi
        USERNAME=$REPLY
    done
    return 0
}

step_timezone() {
    TIMEZONE=$TIMEZONE_ARG
    if [[ -z $TIMEZONE ]]; then
        [[ -z $LIVE ]] && TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || true)
        if [[ -z $TIMEZONE && -n $GUIDED ]]; then
            ui_input "Timezone" "Timezone (Region/City):" America/Toronto
            if went_back; then return 0; fi
            TIMEZONE=${REPLY:-America/Toronto}
            [[ -e /usr/share/zoneinfo/$TIMEZONE || -n $LIVE ]] || warn "unknown timezone '$TIMEZONE'"
            return 0
        fi
        TIMEZONE=${TIMEZONE:-America/Toronto}
    fi
    [[ -e /usr/share/zoneinfo/$TIMEZONE || -n $LIVE ]] || warn "unknown timezone '$TIMEZONE'"
    skip
    return 0
}

# ask_twice "heading" "text" VAR [empty-ok]: a password typed twice; ← on the second one goes back to
# the first. With empty-ok, Enter on both (nothing typed) is an answer too (VAR stays empty)
ask_twice() {
    local head=$1 text=$2 p1
    while true; do
        ui_password "$head" "$text"
        if went_back; then return 0; fi
        p1=$REPLY
        if [[ -z $p1 && -n ${4:-} ]]; then printf -v "$3" '%s' "" && return 0; fi
        ui_password "$head" "Again:"
        if went_back; then WENT_BACK="" && continue; fi
        if [[ -n $p1 && $p1 == "$REPLY" ]]; then printf -v "$3" '%s' "$p1" && return 0; fi
        ui_msg "$head" "Empty, or they do not match. Try again."
    done
}
step_password() {
    PASSWORD=${NIXOS_PASSWORD:-}
    if [[ -n $PASSWORD ]]; then skip && return 0; fi
    if [[ $MODE == resume ]]; then # the user exists already: a new password is optional
        [[ -t 0 || $UI == tui ]] || { skip && return 0; }
        ask_twice "Password" "New password for $USERNAME on NixOS (Enter without typing: keep the current one):" PASSWORD 1
        return 0
    fi
    ask_twice "Password" "Password for $USERNAME on NixOS:" PASSWORD
    return 0
}
unlocks() { printf '%s' "$1" | sudo cryptsetup open --test-passphrase --key-file=- "$ROOT_DEV" 2>/dev/null; } # PASS
step_passphrase() {
    LUKS_PASS=""
    if [[ -z $ENCRYPT ]]; then skip && return 0; fi
    LUKS_PASS=${NIXOS_LUKS_PASSPHRASE:-}
    if [[ $MODE == resume ]]; then # unlock the existing disk: typed once, checked before going on
        if [[ -n $LUKS_PASS ]]; then unlocks "$LUKS_PASS" || die "NIXOS_LUKS_PASSPHRASE does not unlock $ROOT_DEV"; skip && return 0; fi
        while true; do
            ui_password "Disk passphrase" "Passphrase that unlocks $ROOT_DEV (the existing install's disk):"
            if went_back; then return 0; fi
            LUKS_PASS=$REPLY
            if [[ -n $LUKS_PASS ]] && { ! command -v cryptsetup >/dev/null || unlocks "$LUKS_PASS"; }; then break; fi
            ui_msg "Disk passphrase" "That passphrase does not unlock $ROOT_DEV. Try again."
        done
        return 0
    fi
    if [[ -z $LUKS_PASS ]]; then
        while true; do
            ask_twice "Disk passphrase" "Passphrase to unlock NixOS's disk at boot (US keyboard layout; if it's lost, the data is gone):" LUKS_PASS
            if went_back; then return 0; fi
            # The boot prompt uses the US keyboard layout: characters typed differently elsewhere won't match
            [[ $LUKS_PASS =~ ^[[:print:]]+$ ]] && break
            ui_msg "Disk passphrase" "It has characters that can't be typed at the boot prompt. Pick another."
        done
    else
        [[ $LUKS_PASS =~ ^[[:print:]]+$ ]] || die "the disk passphrase has characters that can't be typed at the boot prompt"
        skip
    fi
    return 0
}

# --- Wi-Fi to copy: NixOS is online at its first boot (init.sh, updates and the network menu need it)
EXPORT_WIFI=$NIXOS_DIR/lib/export-wifi.sh
WIFI_SAVED="" WIFI_EMPTY_NOTE=""
step_wifi() {
    local items=() u n a picked w want
    WIFI_UUIDS=() WIFI_NAMES=() WIFI_NOTE=""
    if [[ -z $WIFI_EMPTY_NOTE && -z $WIFI_SAVED ]]; then # read once: it needs root and doesn't change meanwhile
        if ! command -v nmcli >/dev/null || ! WIFI_SAVED=$(sudo bash "$EXPORT_WIFI" --list 2>/dev/null); then
            WIFI_SAVED="" WIFI_EMPTY_NOTE="none (no NetworkManager here): connect on NixOS with nmtui"
        fi
        [[ -n $WIFI_SAVED ]] || WIFI_EMPTY_NOTE=${WIFI_EMPTY_NOTE:-none saved here: connect on NixOS with nmtui}
    fi
    if [[ -z $WIFI_SAVED ]]; then WIFI_NOTE=$WIFI_EMPTY_NOTE && skip && return 0; fi
    if [[ -n $GUIDED && -z $WIFI_ARG ]]; then
        while IFS=$'\t' read -r u n a; do items+=("$u" "$n${a/yes/  (connected now)}" on); done <<<"$(sed 's/\tno$/\t/' <<<"$WIFI_SAVED")"
        ui_checklist "Wi-Fi" "Copy these Wi-Fi networks (with their passwords) to NixOS, so it is online at its first boot?
Each is copied without its access-point lock, so a router that steers the card to another band still works." "${items[@]}"
        if went_back; then return 0; fi
        picked=" $REPLY "
    else
        picked=""
        case ${WIFI_ARG:-active} in
        none) ;;
        all) picked=" $(cut -f1 <<<"$WIFI_SAVED" | paste -sd' ' -) " ;;
        active) picked=" $(awk -F'\t' '$3 == "yes" { print $1 }' <<<"$WIFI_SAVED" | paste -sd' ' -) " ;;
        *)
            IFS=, read -ra want <<<"$WIFI_ARG"
            for w in "${want[@]}"; do
                u=$(awk -F'\t' -v n="$w" '$2 == n { print $1; exit }' <<<"$WIFI_SAVED")
                [[ -n $u ]] || die "--wifi: no saved Wi-Fi named \"$w\" (saved: $(cut -f2 <<<"$WIFI_SAVED" | paste -sd, -))"
                picked+=" $u"
            done
            picked+=" "
            ;;
        esac
        skip
    fi
    while IFS=$'\t' read -r u n _; do
        [[ $picked == *" $u "* ]] && WIFI_UUIDS+=("$u") && WIFI_NAMES+=("$n")
    done <<<"$WIFI_SAVED"
    ((${#WIFI_UUIDS[@]})) || WIFI_NOTE="none: connect on NixOS with nmtui"
    return 0
}

# --- SSH keys to copy (optional): git push / ssh work on NixOS without new keys -------------------
SSH_SRC=$HOME/.ssh
SSH_SAVED=$(bash "$NIXOS_DIR/lib/copy-ssh.sh" --list "$SSH_SRC" 2>/dev/null || true)
step_ssh() {
    local items=() n d picked=" " w want
    SSH_ITEMS=() SSH_NOTE=""
    if [[ -z $SSH_SAVED ]]; then SSH_NOTE="none (nothing in $SSH_SRC)" && skip && return 0; fi
    if [[ -n $GUIDED && -z $SSH_ARG ]]; then
        while IFS=$'\t' read -r n d; do items+=("$n" "$(printf '%-18s %s' "$n" "$d")" on); done <<<"$SSH_SAVED"
        ui_checklist "SSH keys" "Copy these from $SSH_SRC to your NixOS home? (optional; untick all with a)
Private keys are copied as they are, with their passphrase if they have one, readable by you only." "${items[@]}"
        if went_back; then return 0; fi
        picked=" $REPLY "
    else
        case ${SSH_ARG:-none} in
        none) ;;
        all) picked=" $(cut -f1 <<<"$SSH_SAVED" | paste -sd' ' -) " ;;
        *)
            IFS=, read -ra want <<<"$SSH_ARG"
            for w in "${want[@]}"; do
                grep -qxF "$w" < <(cut -f1 <<<"$SSH_SAVED") || die "--ssh: no key or ssh file named \"$w\" in $SSH_SRC (there: $(cut -f1 <<<"$SSH_SAVED" | paste -sd, -))"
                picked+="$w "
            done
            ;;
        esac
        skip
    fi
    while IFS=$'\t' read -r n _; do [[ $picked == *" $n "* ]] && SSH_ITEMS+=("$n"); done <<<"$SSH_SAVED"
    ((${#SSH_ITEMS[@]})) || SSH_NOTE="none"
    return 0
}

# --- summary, warnings, confirmation --------------------------------------------------------------
step_plan_summary() { # works out the summary lines and what will be typed to confirm
    local model disk_line sz p d u
    model=$(lsblk -dno MODEL "$DISK" 2>/dev/null | sed 's/ *$//' || true)
    disk_line="$DISK${model:+  $model}  $(lsblk -dno SIZE "$DISK" | tr -d ' ')"
    # "#Title" lines start a section (a card in the TUI, a divider in the scrollback box)
    lines=("#NixOS" "Host      $HOST ($host_system)" "User      $USERNAME" "Timezone  $TIMEZONE")
    if [[ -n $ENCRYPT ]]; then
        lines+=("Storage   encrypted: LUKS2 (passphrase at boot) + Btrfs: @ @home @nix @log, zstd")
    else
        lines+=("Storage   ext4, not encrypted")
    fi
    lines+=("#Disk  $disk_line")
    case $MODE in
    resume)
        lines+=("Kept      $(describe "$BOOT_DEV" | sed 's/ *(.*)$//')  (EFI, not formatted)"
            "Kept      $(describe "$ROOT_DEV" | sed 's/ *(.*)$//')  (NixOS, not formatted)")
        lines+=("Continue  /etc/nixos written again, build + install (what is built is reused), home setup")
        [[ -n $PASSWORD ]] || lines+=("          $USERNAME's password: kept as it is")
        CONFIRM="continue $(basename "$ROOT_DEV")"
        ;;
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
    delete)
        for p in "${DELETE_PARTS[@]}"; do lines+=("DELETED   $(describe "$p" | sed 's/ *(.*)$//')"); done
        sz=${NIXOS_GIB:+$NIXOS_GIB GiB}
        lines+=("New       1 GiB EFI (NIXBOOT) + NixOS (nixos) ${sz:-on all $(gib $(((FREE_END - FREE_START + 1) * $(sector_size "$DISK") - GiB))) GiB} in the space freed")
        CONFIRM="delete$(for p in "${DELETE_PARTS[@]}"; do printf ' %s' "$(basename "$p")"; done)" # e.g. "delete sda2 sda3"
        ;;
    parts)
        lines+=("Formatted ${BOOT_DEV##*/}  $(lsblk -dno SIZE "$BOOT_DEV" | tr -d ' ')  -> EFI (NIXBOOT)"
            "Formatted ${ROOT_DEV##*/}  $(lsblk -dno SIZE "$ROOT_DEV" | tr -d ' ')  -> NixOS (nixos)")
        CONFIRM=$(basename "$ROOT_DEV")
        ;;
    esac
    if [[ $MODE != erase ]]; then
        for p in $(parts_of "$DISK"); do
            [[ $p == "${BOOT_DEV:-}" || $p == "${ROOT_DEV:-}" || $p == "$SHRINK_PART" || " ${DELETE_PARTS[*]} " == *" $p "* ]] && continue
            lines+=("Kept      $(describe "$p" | sed 's/ *(.*)$//')")
        done
    fi
    [[ -n $NEED_GPT ]] && lines+=("Converted $DISK MBR -> GPT in place (partitions kept)")
    for p in ${RELEASE[@]+"${RELEASE[@]}"}; do lines+=("Unmounted $(basename "$p") from $(mounted_in "$p")$([[ $MODE == shrink ]] && echo ', remounted after' || true)"); done
    lines+=("#Copied to NixOS"
        "Wi-Fi     ${WIFI_NOTE:-$(IFS=,; echo "${WIFI_NAMES[*]}" | sed 's/,/, /g')}"
        "SSH       ${SSH_NOTE:-$(IFS=,; echo "${SSH_ITEMS[*]}" | sed 's/,/, /g') -> ~/.ssh}"
        "Dotfiles  this checkout -> ~/nodestack/dotfiles, configs linked (Hyprland + Caelestia ready)")
    local others=()
    while read -r d; do
        [[ $d == "$DISK" ]] && continue
        if is_sys_disk "$d"; then others+=("Untouched $d  $(lsblk -dno SIZE "$d" | tr -d ' ')  (running system: $RUNNING_OS)")
        elif [[ -n $(os_problem "$d") ]]; then others+=("Untouched $d  $(lsblk -dno SIZE "$d" | tr -d ' ')  (another OS)"); fi
    done < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }')
    ((${#others[@]})) && lines+=("#Other disks" "${others[@]}")
    STALE_UUIDS=()
    if [[ $MODE == erase && -n $(parts_of "$DISK") ]]; then
        CONFIRM="erase $(basename "$DISK")"
        for p in $(parts_of "$DISK"); do
            u=$(lsblk -dno PARTUUID "$p")
            [[ -n $u && -n $(boot_entry_of "$p") ]] && STALE_UUIDS+=("$u")
        done
    fi
    if [[ $MODE == delete ]]; then # the firmware entries of deleted boot partitions go too
        for p in "${DELETE_PARTS[@]}"; do
            u=$(lsblk -dno PARTUUID "$p")
            [[ -n $u && -n $(boot_entry_of "$p") ]] && STALE_UUIDS+=("$u")
        done
    fi
    skip
    return 0
}

contents_of() { # yes|no: the lines of `contents` for the partitions that are (yes, in yellow) /
    local line d hit # aren't (no, in green) deleted
    while IFS= read -r line; do
        line=${line#"$WARN_MARK"} hit=no
        for d in "${DELETE_PARTS[@]}"; do if [[ $line == "  $(basename "$d") "* ]]; then hit=yes; fi; done
        if [[ $hit == "$1" ]]; then printf '%s%s\n' "$([[ $1 == yes ]] && echo "$WARN_MARK" || echo "$OK_MARK")" "$line"; fi
    done < <(contents "$DISK")
    return 0
}
step_warning() { # what an erase / a delete destroys, spelled out
    local warning p
    if [[ $MODE == delete ]]; then
        warning="These partitions of $DISK will be DELETED, with all their data:"$'\n\n'"$(contents_of yes)"
        warning+=$'\n\n'"Kept as they are:"$'\n'"$(contents_of no)"
        [[ -n $OS_REASON ]] && warning+=$'\n\n'"The other OS on this disk (${OS_REASON#*: }) will no longer boot."
        ((${#STALE_UUIDS[@]})) && warning+=$'\n'"The firmware boot entries of the deleted partitions will be removed after the install."
        [[ -z $LIVE ]] && grep -qE "$(for p in "${DELETE_PARTS[@]}"; do lsblk -dno UUID "$p"; done | grep . | paste -sd'|' -)" /etc/fstab 2>/dev/null &&
            warning+=$'\n'"This system's /etc/fstab mounts some of them: remove those lines after the install."
        warning+=$'\n\n'"Make sure anything you need from them is backed up."
        if [[ -n ${NIXOS_INSTALL_YES:-} ]]; then plain_text "$warning" >&2 && skip && return 0; fi
        if ! ui_yesno "WARNING: data loss" "$warning" "I understand" "Cancel"; then went_back || die "cancelled"; fi
        return 0
    fi
    if [[ $MODE != erase || -z $(parts_of "$DISK") ]]; then skip && return 0; fi
    warning="EVERYTHING on $DISK will be destroyed:"$'\n\n'"$(mark_lines "$WARN_MARK" "$(contents "$DISK")")"
    [[ -n $OS_REASON ]] && warning+=$'\n\n'"This is a clean install over an existing system: ${OS_REASON#*: }."$'\n'"That system and all its files will be gone, and it will no longer boot."
    ((${#STALE_UUIDS[@]})) && warning+=$'\n'"Its firmware boot entries will be removed after the install."
    [[ -z $LIVE ]] && grep -qE "$(parts_of "$DISK" | while read -r p; do lsblk -dno UUID "$p"; done | grep . | paste -sd'|' -)" /etc/fstab 2>/dev/null &&
        warning+=$'\n'"This system's /etc/fstab mounts partitions of $DISK: remove those lines after the install."
    warning+=$'\n\n'"Make sure anything you need from it is backed up."
    if [[ -n ${NIXOS_INSTALL_YES:-} ]]; then
        plain_text "$warning" >&2
        skip && return 0
    fi
    if ! ui_yesno "WARNING: data loss" "$warning" "I understand" "Cancel"; then
        went_back || die "cancelled"
    fi
    return 0
}

step_summary() {
    if [[ $UI == tui ]]; then
        local ok=0
        SCREEN_SUMMARY=1
        ui_yesno "Summary" "Red: destroyed · yellow: changed, data kept · green: created or kept · blue: copied.
Continue? A last yes / no names what is changed on the disk; after it the install runs to the
end without more questions." "Continue" "Cancel" || ok=$?
        SCREEN_SUMMARY=""
        if ((ok)); then went_back || die "cancelled"; fi
    else
        echo
        box "Install NixOS${LIVE:+ (from a live system)}" "${lines[@]}"
        skip
    fi
    return 0
}

what_changes() { # one line: what the disk step destroys or changes, e.g. "Deleting: sda2, sda3"
    local names
    case $MODE in
    resume) echo "Continuing the install on $(basename "$BOOT_DEV") + $(basename "$ROOT_DEV") (nothing is formatted)" ;;
    erase) echo "Erasing: all of $(basename "$DISK")$([[ -n $(parts_of "$DISK") ]] && echo " ($(parts_of "$DISK" | xargs -n1 basename | paste -sd, - | sed 's/,/, /g'))" || true)" ;;
    delete)
        names=$(for p in "${DELETE_PARTS[@]}"; do basename "$p"; done | paste -sd, - | sed 's/,/, /g')
        echo "Deleting: $names"
        ;;
    parts) echo "Formatting: $(basename "$BOOT_DEV"), $(basename "$ROOT_DEV")" ;;
    shrink) echo "Shrinking: $(basename "$SHRINK_PART") to $SHRINK_GIB GiB (data kept)" ;;
    free) echo "Creating: 2 partitions in the free space of $(basename "$DISK") (nothing deleted)" ;;
    esac
}
step_confirm() { # the point of no return: after this the disk is changed
    if [[ -n ${NIXOS_INSTALL_YES:-} ]]; then skip && return 0; fi
    if [[ $UI == tui ]]; then # a last yes / no, naming what changes; Yes is pre-selected
        MENU_DEFAULT=yes
        ui_menu "Confirm" "$(what_changes)

Proceed? After this there is no going back: the disk is changed and the install
runs to the end. No (or ←) goes back to the summary; nothing has been changed so far." yes "Yes, proceed" no "No"
        MENU_DEFAULT=""
        if went_back || [[ $REPLY == no ]]; then WENT_BACK=1; fi
        return 0
    fi
    while true; do # numbered / piped mode: the name is typed (scripts can pipe it)
        read -rp "Type ${B}$CONFIRM${R} to continue (< back): " REPLY || die "cancelled" # stdin: can be piped
        WENT_BACK=""
        [[ $REPLY == "<" ]] && WENT_BACK=1
        if went_back; then return 0; fi
        [[ $REPLY == "$CONFIRM" ]] && break
        [[ -n $REPLY ]] || continue
        die "cancelled (typed \"$REPLY\", expected \"$CONFIRM\")"
    done
    return 0
}

# --- the driver -------------------------------------------------------------------------------------
QUESTIONS=(step_host step_disk step_existing step_layout step_encrypt step_details step_plan_args step_validate
    step_user step_timezone step_password step_passphrase step_wifi step_ssh step_plan_summary
    step_warning step_summary step_confirm)
# Steps that only work things out: when going back they are passed over (they run again going forward)
AUTO_STEPS=" step_plan_args step_validate step_plan_summary "
run_steps() {
    local i=0 dir=1 k crumb_of=()
    while ((i < ${#QUESTIONS[@]})); do
        CRUMBS=()
        for ((k = 0; k < i; k++)); do [[ -n ${crumb_of[k]:-} ]] && CRUMBS+=("${crumb_of[k]}"); done
        WENT_BACK="" SKIPPED="" STEP_CRUMB=""
        if ((dir < 0)) && [[ $AUTO_STEPS == *" ${QUESTIONS[i]} "* ]]; then
            SKIPPED=1 STEP_CRUMB=${crumb_of[i]:-}
        else
            "${QUESTIONS[i]}"
        fi
        if went_back; then
            crumb_of[i]="" dir=-1 i=$((i - 1))
        else
            crumb_of[i]=$STEP_CRUMB
            if [[ -n $SKIPPED ]]; then i=$((i + dir)); else dir=1 i=$((i + 1)); fi
        fi
        if ((i < 0)); then # ← on the first screen
            if ui_yesno "Quit?" "This is the first screen: there is nothing to go back to.
Quit the installer? Nothing has been changed." "Quit" "Stay"; then
                die "cancelled"
            fi
            i=0 dir=1
        fi
    done
    CRUMBS=()
    for k in "${!crumb_of[@]}"; do [[ -n ${crumb_of[k]} ]] && CRUMBS+=("${crumb_of[k]}"); done
    return 0
}
if [[ -n $RUN_PLAN ]]; then # the background service: the answers come from the plan, read once
    # shellcheck source=/dev/null
    . "$RUN_PLAN"
    rm -f "$RUN_PLAN"
    echo
    box "Install NixOS${LIVE:+ (from a live system)}" "${lines[@]}"
else
    trap 'die cancelled' INT # Ctrl-C in the menus: same as q
    run_steps
    trap - INT
    if [[ $UI == tui ]]; then # the summary was on a TUI screen: keep it in the scrollback
        clear && TUI_SHOWN=""
        box "Install NixOS${LIVE:+ (from a live system)}" "${lines[@]}"
    fi
    # From here on nothing asks anything: the install goes on in the background, so the
    # terminal can be closed (lib/background.sh); scripts and piped input stay in the foreground
    if bg_can_detach; then
        bg_launch
        exit $?
    fi
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
    "github:nixos/nixpkgs/$rev#gptfdisk" "github:nixos/nixpkgs/$rev#efibootmgr" \
    ${ENCRYPT:+"github:nixos/nixpkgs/$rev#cryptsetup" "github:nixos/nixpkgs/$rev#btrfs-progs"})
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

TABLE_BACKUP=${USER_HOME:-$HOME}/$(basename "$DISK")-partition-table-$(date +%Y%m%d-%H%M%S).sfdisk
# unmount everything, then close the LUKS mapping (on exit, also after an error)
cleanup_mnt() {
    sudo umount -R "$MNT" 2>/dev/null || true
    if [[ -n $ENCRYPT && -e /dev/mapper/$LUKS_NAME ]]; then as_root cryptsetup close "$LUKS_NAME" 2>/dev/null || true; fi
    return 0
}
mount_subvols() { # DEV: Btrfs subvolumes @ @home @nix @log on MNT (and /boot's mount point)
    local opts=compress=zstd,noatime
    sudo mount -o "subvol=@,$opts" "$1" "$MNT"
    sudo mkdir -p "$MNT/home" "$MNT/nix" "$MNT/var/log" "$MNT/boot"
    sudo mount -o "subvol=@home,$opts" "$1" "$MNT/home"
    sudo mount -o "subvol=@nix,$opts" "$1" "$MNT/nix"
    sudo mount -o "subvol=@log,$opts" "$1" "$MNT/var/log"
}
if [[ $MODE == resume ]]; then
    # --- 3 + 4 when continuing an existing install: mount it as it is, nothing formatted -------
    STEP=3
    step "Mounting the existing install: $(basename "$BOOT_DEV") (EFI) + $(basename "$ROOT_DEV") (NixOS), nothing formatted"
    for p in "$BOOT_DEV" "$ROOT_DEV"; do
        [[ /dev/$(lsblk -dno PKNAME "$p") == "$DISK" ]] || die "$p is not on $DISK: stopping"
        is_sys_disk "$DISK" && die "$p is on the running system's disk: stopping"
    done
    sudo mkdir -p "$MNT"
    trap cleanup_mnt EXIT
    root_fs=$ROOT_DEV
    if [[ -n $ENCRYPT ]]; then
        info "Unlocking $ROOT_DEV"
        printf '%s' "$LUKS_PASS" | as_root cryptsetup open --key-file=- "$ROOT_DEV" "$LUKS_NAME" ||
            die "could not unlock $ROOT_DEV (wrong passphrase?)"
        root_fs=/dev/mapper/$LUKS_NAME
    fi
    if [[ $(lsblk -dno FSTYPE "$root_fs") == btrfs ]]; then mount_subvols "$root_fs"
    else sudo mount "$root_fs" "$MNT" && sudo mkdir -p "$MNT/boot"; fi
    sudo mount -o umask=077 "$BOOT_DEV" "$MNT/boot"
    echo "  mounted on $MNT"
else
step "Disk: $MODE $DISK"
REMOUNT=""
[[ $MODE == shrink && -n $(mounted_in "$SHRINK_PART") ]] && REMOUNT=$(mounted_in "$SHRINK_PART")
release
if [[ $MODE != erase ]]; then
    # shellcheck disable=SC2024 # written as you, into your home
    sudo sfdisk -d "$DISK" >"$TABLE_BACKUP" 2>/dev/null && echo "  partition table saved to $TABLE_BACKUP"
    [[ -z ${USER_IDS:-} || ! -f $TABLE_BACKUP ]] || chown "$USER_IDS" "$TABLE_BACKUP" # background: written as root
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
delete)
    # Numbers first, then deleted from the highest down: on MBR, deleting a logical partition
    # renumbers the ones after it
    nums=$(for p in "${DELETE_PARTS[@]}"; do cat "/sys/class/block/$(basename "$p")/partition"; done | sort -rn)
    for p in "${DELETE_PARTS[@]}"; do as_root wipefs -aq "$p" || true; done
    for n in $nums; do
        info "Deleting $(basename "$(part "$DISK" "$n")")"
        as_root sfdisk --no-reread -q --delete "$DISK" "$n"
        as_root partx -d --nr "$n" "$DISK" 2>/dev/null || true # the kernel forgets it, other partitions may be in use
    done
    reread
    for p in "${DELETE_PARTS[@]}"; do [[ ! -b $p ]] || warn "the kernel still shows $p (it will be gone after a reboot)"; done
    [[ -n $NEED_GPT ]] && convert_gpt
    plan_free "$DISK"
    make_nixos_parts "$FREE_START" "$FREE_END"
    ;;
parts) echo "  using $BOOT_DEV and $ROOT_DEV as they are" ;;
esac

# --- 4. format + mount ---------------------------------------------------------------------------
step "Formatting $BOOT_DEV (EFI) and $ROOT_DEV (NixOS)"
# (cleanup_mnt and mount_subvols are defined before step 3)
for p in "$BOOT_DEV" "$ROOT_DEV"; do
    [[ /dev/$(lsblk -dno PKNAME "$p") == "$DISK" ]] || die "$p is not on $DISK: stopping"
    is_sys_disk "/dev/$(lsblk -dno PKNAME "$p")" && die "$p is on the running system's disk: stopping"
done
as_root mkfs.fat -F 32 -n NIXBOOT "$BOOT_DEV" >/dev/null
sudo mkdir -p "$MNT"
if [[ -n $ENCRYPT ]]; then
    # --encrypt: LUKS2 on the NixOS partition, Btrfs inside, one subvolume per mount point
    [[ ! -e /dev/mapper/$LUKS_NAME ]] || die "/dev/mapper/$LUKS_NAME is already open on this system: close it first (sudo cryptsetup close $LUKS_NAME)"
    info "Encrypting $ROOT_DEV (LUKS2)"
    # the passphrase goes through stdin, never on a command line
    printf '%s' "$LUKS_PASS" | as_root cryptsetup luksFormat --type luks2 --label "$LUKS_LABEL" \
        --batch-mode --key-file=- "$ROOT_DEV"
    printf '%s' "$LUKS_PASS" | as_root cryptsetup open --key-file=- "$ROOT_DEV" "$LUKS_NAME"
    trap cleanup_mnt EXIT
    CRYPT_DEV=/dev/mapper/$LUKS_NAME
    as_root mkfs.btrfs -q -f -L nixos "$CRYPT_DEV"
    sudo mount "$CRYPT_DEV" "$MNT"
    for sv in @ @home @nix @log; do as_root btrfs -q subvolume create "$MNT/$sv"; done
    sudo umount "$MNT"
    mount_subvols "$CRYPT_DEV"
else
    as_root mkfs.ext4 -qF -L nixos "$ROOT_DEV"
    sudo mount "$ROOT_DEV" "$MNT"
    sudo mkdir -p "$MNT/boot"
fi
sudo mount -o umask=077 "$BOOT_DEV" "$MNT/boot"
trap cleanup_mnt EXIT
echo "  mounted on $MNT"
fi # (new install / continuing an existing one)
if [[ -n ${NIXOS_INSTALL_STOP_AFTER_DISK:-} ]]; then # tests only
    findmnt -R -o TARGET,SOURCE,FSTYPE,OPTIONS "$MNT" | cut -c1-140
    cleanup_mnt && trap - EXIT
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,UUID "$DISK"
    exit 0
fi

# --- 5. config ------------------------------------------------------------------------------------
step "Writing $MNT/etc/nixos"
as_root bash "$NIXOS_DIR/lib/write-config.sh" "$MNT" "$USERNAME" "$TIMEZONE"
# nixos-generate-config lists every active swap, including this system's
# (e.g. another distro's encrypted swap; a live CD: zram), which NixOS would then wait for at boot
sudo sed -z -i 's/swapDevices[[:space:]]*=[[:space:]]*\[[^]]*\];/swapDevices = [ ];/' \
    "$MNT/etc/nixos/hardware-configuration.nix"
if [[ -n $ENCRYPT ]]; then
    HWCONF=$MNT/etc/nixos/hardware-configuration.nix
    # nixos-generate-config keeps subvol= but not the other mount options
    sudo sed -i 's/"subvol=\(@[a-z]*\)"/"subvol=\1" "compress=zstd" "noatime"/g' "$HWCONF"
    # Without the LUKS entry the initrd can't unlock the disk: NixOS wouldn't boot
    sudo grep -q 'boot.initrd.luks.devices' "$HWCONF" ||
        die "nixos-generate-config did not add boot.initrd.luks.devices to $HWCONF: stopping before the install"
    [[ $(sudo grep -c '"compress=zstd"' "$HWCONF") -ge 4 ]] || warn "compress=zstd was not added to every Btrfs mount in $HWCONF"
    echo "  LUKS unlock and Btrfs mounts in hardware-configuration.nix:"
    sudo grep -E 'luks.devices|subvol=' "$HWCONF" | sed 's/^ */    /'
fi

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
if [[ -n $PASSWORD ]]; then echo "$USERNAME:$PASSWORD" | in_nixos chpasswd; else echo "  password of $USERNAME: kept as it is"; fi
uid_gid=$(in_nixos "id -u $USERNAME; id -g $USERNAME" | grep -E '^[0-9]+$' | paste -sd: -)
[[ $uid_gid =~ ^[0-9]+:[0-9]+$ ]] || die "could not read the uid / gid of $USERNAME on NixOS"
sudo mkdir -p "$MNT/home/$USERNAME/nodestack"
target_checkout=$MNT/home/$USERNAME/nodestack/dotfiles
if [[ $MODE == resume && -e $target_checkout ]]; then
    # an install in use: its checkout may hold work of its own, so it is kept aside, not deleted
    aside=$target_checkout.bak-$(date +%Y%m%d-%H%M%S)
    sudo mv "$target_checkout" "$aside"
    echo "  the checkout already on NixOS moved to ~/nodestack/$(basename "$aside")"
fi
sudo rm -rf "$target_checkout"
sudo cp -a "$DOTFILES" "$target_checkout"
sudo chown -R "$uid_gid" "$MNT/home/$USERNAME"
# Link the configs now, so the first login has Hyprland's config (it starts Caelestia),
# and do the home's one-time setup: a fresh install needs nothing run after it
info "Linking the dotfiles into /home/$USERNAME"
sudo bash "$NIXOS_DIR/lib/link-dotfiles.sh" --root "$MNT" --user "$USERNAME" --owner "$uid_gid"
info "Setting up /home/$USERNAME (Copilot flag, tmux plugin manager, zsh completions)"
sudo bash "$NIXOS_DIR/lib/home-setup.sh" --root "$MNT" --user "$USERNAME" --owner "$uid_gid" ||
    warn "the home setup failed: run bash ~/nodestack/dotfiles/nixos/init.sh on NixOS"
if ((${#SSH_ITEMS[@]})); then
    info "Copying SSH keys"
    sudo bash "$NIXOS_DIR/lib/copy-ssh.sh" "$SSH_SRC" "$MNT/home/$USERNAME/.ssh" "$uid_gid" "${SSH_ITEMS[@]}"
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
# A reformatted EFI partition keeps its partition GUID, so the firmware entries of the boot
# loader it held before (e.g. systemd-boot, before Limine) still point at it, at files that
# are gone. Done after the install: only entries whose file is really missing are removed
# (the install itself writes Limine and the fallback EFI/BOOT/BOOTX64.EFI).
boot_uuid=$(lsblk -dno PARTUUID "$BOOT_DEV")
if [[ -n $boot_uuid ]]; then
    while IFS=$'\t' read -r num file; do
        [[ -n $file ]] || continue
        if [[ -z $(sudo find "$MNT/boot" -ipath "$MNT/boot/$file" -print -quit 2>/dev/null) ]]; then
            info "Removing the firmware boot entry Boot$num (its file $file is gone from the EFI partition)"
            as_root efibootmgr -q -b "$num" -B
        fi
    done < <(as_root efibootmgr -v | grep -i "HD([0-9]*,GPT,$boot_uuid" |
        sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*HD([^)]*)\/\(File(\)\{0,1\}\(\\[^ )]*\.[Ee][Ff][Ii]\).*/\1\t\3/p' |
        sed 's/\\/\//g; s/\t\//\t/')
fi
# Entries whose device path is only a vendor placeholder (no disk, no file) are left from
# installs that are gone on some firmware (AMI); they're listed, not removed, since that
# format is firmware-specific
ORPHAN_ENTRIES=$(as_root efibootmgr -v | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} \(.*\)\tVenHw([^)]*)$/\1 \2/p' || true)

cleanup_mnt
trap - EXIT

# --- done -------------------------------------------------------------------------------------------
boot_now=$(as_root efibootmgr 2>/dev/null || true)
nixos_entry=$(sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Limine.*/\1/p' <<<"$boot_now" | head -1)
order=$(sed -n 's/^BootOrder: //p' <<<"$boot_now")
done_lines=()
[[ -n $LIVE ]] && done_lines+=("0. Remove the live CD / USB")
done_lines+=("1. Reboot, open the firmware boot menu (F8 / F11 / F12) and pick"
    "     \"Limine\" on ${model:-$DISK} ($DISK)"
    "2. Log in as $USERNAME: everything is set up, nothing else to run"
    "3. Change the password if it was a temporary one: passwd"
    "" "Later: bash ~/nodestack/dotfiles/nixos/init.sh applies updates (after a git pull);"
    "after gh auth login, it also adds the gh copilot extension.")
[[ -f $TABLE_BACKUP ]] && done_lines+=("" "Old partition table of $DISK: $TABLE_BACKUP")
((${#WIFI_UUIDS[@]})) || done_lines+=("" "No Wi-Fi was copied: on NixOS, connect with nmtui (or plug in a cable)")
[[ -n $ENCRYPT ]] && done_lines+=("" "The boot asks for the disk passphrase on the splash (US keyboard layout),"
    "then shows Caelestia's lock screen: unlock it with $USERNAME's password.")
if [[ -n $ORPHAN_ENTRIES ]]; then
    done_lines+=("" "Firmware entries that point at no disk (left from old installs?):")
    while read -r num name; do done_lines+=("     Boot$num $name"); done <<<"$ORPHAN_ENTRIES"
    done_lines+=("  remove one with: sudo efibootmgr -b NNNN -B")
fi
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
