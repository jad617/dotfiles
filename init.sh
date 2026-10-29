#!/usr/bin/env bash
# =============================================================================
# Idempotent dotfiles bootstrap — macOS & Ubuntu (incl. Pop!_OS), x86_64 & arm64
#
# Usage: see usage() below, or ./init.sh --help
#
# On a fresh machine:
#   bash <(curl -fsSL https://raw.githubusercontent.com/jad617/dotfiles/main/init.sh)
#
# Safe to re-run: every step checks the current state first.
# Must stay compatible with macOS's stock bash 3.2 (no assoc arrays, no
# mapfile, guard empty-array expansions under set -u).
# =============================================================================
set -Eeuo pipefail

SECTIONS="base devops shell links"

omit_file_pretty() { local f="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/omitted-apps"; printf '%s' "${f/#"$HOME"/\~}"; }

usage() {
    cat <<EOF
Usage: ./init.sh [mode] [options]

Modes:
  (none)              install what's missing; never upgrades (default)
  --upgrade, -u       also upgrade everything it manages to the latest
  --dry-run, -n       show what install/upgrade would change; change nothing
  --doctor            check the setup: PATH shadowing, apt keys, links, shell
  --select            only edit the app checklist (saved); install nothing

Options:
  --only <list>       run only these sections (comma-separated)
  --skip <list>       skip these sections
                      sections: ${SECTIONS// /, }
  --yes, -y           skip the app checklist and use the saved choices
                      (alias --non-interactive; automatic without a terminal)
  --omit-app <list>   stop installing / upgrading these apps (saved)
  --add-app <list>    manage these omitted apps again (saved)
  --verbose, -v       stream every command's output instead of logging it
  --help, -h          show this help

Examples:
  ./init.sh --upgrade --only devops
  ./init.sh --upgrade --dry-run
  ./init.sh --omit-app wezterm,dotnet

Omitted apps are remembered in $(omit_file_pretty) and are never
uninstalled, only no longer installed or upgraded. Every interactive run
starts with the app checklist, pre-set from the saved choices (skip it
with --yes).
EOF
}

UPGRADE=false
VERBOSE=false
DRY_RUN=false
DOCTOR=false
ONLY=""
SKIP=""
SELECT=false
ASSUME_YES=false
OMIT_ADD=""
OMIT_DEL=""
while (($#)); do
    case "$1" in
    install | --install) ;;
    upgrade | --upgrade | -u) UPGRADE=true ;;
    -n | --dry-run) DRY_RUN=true ;;
    doctor | --doctor) DOCTOR=true ;;
    -v | --verbose) VERBOSE=true ;;
    --select) SELECT=true ;;
    -y | --yes | --non-interactive) ASSUME_YES=true ;;
    --omit-app=*) OMIT_ADD+=",${1#*=}" ;;
    --add-app=*) OMIT_DEL+=",${1#*=}" ;;
    --omit-app | --add-app)
        [[ -n "${2:-}" ]] || {
            echo "$1 needs a comma-separated list of apps"
            exit 1
        }
        if [[ "$1" == --omit-app ]]; then OMIT_ADD+=",$2"; else OMIT_DEL+=",$2"; fi
        shift
        ;;
    --only=*) ONLY=${1#*=} ;;
    --skip=*) SKIP=${1#*=} ;;
    --only | --skip)
        [[ -n "${2:-}" ]] || {
            echo "$1 needs a section list ($SECTIONS)"
            exit 1
        }
        if [[ "$1" == --only ]]; then ONLY=$2; else SKIP=$2; fi
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        echo
        usage
        exit 1
        ;;
    esac
    shift
done
for s in ${ONLY//,/ } ${SKIP//,/ }; do
    [[ " $SECTIONS " == *" $s "* ]] || {
        echo "Unknown section: $s (sections: $SECTIONS)"
        exit 1
    }
done

if $DOCTOR; then
    MODE=doctor
elif $UPGRADE; then
    MODE=upgrade
else
    MODE=install
fi

# Run from a checkout → use it. Piped from curl (`bash <(curl …)`) the script
# lives in /dev/fd, so fall back to the standard clone location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -d "$SCRIPT_DIR/.git" && -f "$SCRIPT_DIR/init.sh" ]]; then
    DOTFILES="$SCRIPT_DIR"
else
    DOTFILES="$HOME/nodestack/dotfiles"
fi

# -----------------------------------------------------------------------------
# Detect OS + architecture
# -----------------------------------------------------------------------------
OS=""
OS_NAME=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null || true)"
elif [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" == "nixos" ]]; then
        echo "==> NixOS detected — delegating to nixos/init.sh"
        [[ -x "$DOTFILES/nixos/init.sh" ]] || {
            echo "Clone the repo first: git clone https://github.com/jad617/dotfiles.git $DOTFILES"
            exit 1
        }
        exec "$DOTFILES/nixos/init.sh"
    elif [[ "${ID:-}" == "ubuntu" ]]; then
        OS="linux"
        OS_NAME="Ubuntu ${VERSION_ID:-}"
    elif [[ " ${ID_LIKE:-} " == *" ubuntu "* ]]; then
        OS=$([[ "${ID:-}" == "pop" ]] && echo popos || echo linux)
        OS_NAME="Ubuntu ${VERSION_ID:-} (${NAME:-$ID})"
    else
        OS="linux"
        OS_NAME="${PRETTY_NAME:-${NAME:-Linux}} (not Ubuntu — untested)"
    fi
fi

[[ -z "$OS" ]] && {
    echo "Unsupported OS: $OSTYPE (supported: macOS, Ubuntu)"
    exit 1
}

# ARCH: Debian / Go spelling (amd64, arm64); UARCH: uname / Rust spelling.
case "$(uname -m)" in
x86_64 | amd64) ARCH=amd64 UARCH=x86_64 ;;
arm64 | aarch64) ARCH=arm64 UARCH=aarch64 ;;
*)
    echo "Unsupported architecture: $(uname -m) (supported: x86_64, arm64)"
    exit 1
    ;;
esac

# Where this script installs things — on PATH for the run, so re-runs see them.
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.fzf/bin:$PATH"
[[ "$OS" != "macos" ]] && export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# -----------------------------------------------------------------------------
# Output — the terminal gets a compact checklist; every command's own output
# goes to a log file (or straight through with --verbose).
# -----------------------------------------------------------------------------
COLS=$(tput cols 2>/dev/null || echo 80)
((COLS > 100)) && COLS=100
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG="$LOG_DIR/init-$(date +%Y%m%d-%H%M%S).log"
exec 3>&1 4>&2
if ! $VERBOSE; then
    mkdir -p "$LOG_DIR"
    # Keep the 10 most recent logs
    ls -1t "$LOG_DIR"/init-*.log 2>/dev/null | tail -n +10 | xargs rm -f || true
    exec >>"$LOG" 2>&1
fi

if [[ -t 3 && -z "${NO_COLOR:-}" ]]; then
    TTY=true
    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m' C_CYAN=$'\e[36m'
else
    TTY=false
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi
SPIN=$($TTY && ! $VERBOSE && echo true || echo false)

N_INSTALLED=0 N_UPGRADED=0 N_OK=0 N_MAYBE=0 N_WARN=0 N_ERR=0 LINKS_OK=0
SECTION_OK=() SECTION_OMIT=() INSTALLED_LIST=() UPGRADED_LIST=() MAYBE_LIST=() STEP_TIMES=()
STEP_LABEL="" STEP_VERB="" STEP_BIN="" STEP_SUM="" STEP_VER="" STEP_START=0
LATEST_VER=""
SPIN_PID="" SUDO_PID="" SHELL_CHANGED=false PICKER_ON=false STTY_OLD=""

out() { printf '%s\n' "$*" >&3; }
pretty_path() { printf '%s' "${1/#"$HOME"/\~}"; }
cmd_exists() { command -v "$1" &>/dev/null; }

fmt_time() {
    local s=$1
    if ((s >= 60)); then printf '%dm%02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}

# Wrap text to the terminal width; continuation lines get the given indent.
wrap() {
    local indent=$1 text=$2
    printf '%s\n' "$text" | fold -s -w $((COLS - ${#indent} - 2)) | sed "2,\$s/^/$indent/"
}

# One row of a ╭│╰ panel: panel_row <corner> <label> <value>
panel_row() {
    local value
    value=$(wrap "  $(printf '%*s' 14 '')" "$3")
    out "  $1 $(printf '%-10s' "$2") $value"
}

# Join list items with a separator: join <sep> <items…>
join() {
    local sep=$1 res=""
    shift
    while (($#)); do
        res+="${res:+$sep}$1"
        shift
    done
    printf '%s' "$res"
}

# Things already in the wanted state are collected and printed as one dim line.
ok() {
    SECTION_OK+=("$1")
    N_OK=$((N_OK + 1))
}

flush_ok() {
    if ((${#SECTION_OK[@]})); then
        wrap "    " "up to date: $(join ", " "${SECTION_OK[@]}")" |
            sed "1s/^/  ${C_DIM}· /; 2,\$s/^/${C_DIM}/; s/\$/${C_RESET}/" >&3
        SECTION_OK=()
    fi
    if ((${#SECTION_OMIT[@]})); then
        wrap "    " "omitted: $(join ", " "${SECTION_OMIT[@]}")" |
            sed "1s/^/  ${C_DIM}− /; 2,\$s/^/${C_DIM}/; s/\$/${C_RESET}/" >&3
        SECTION_OMIT=()
    fi
}

warn() {
    N_WARN=$((N_WARN + 1))
    out "  ${C_YELLOW}!${C_RESET} $1${2:+ ${C_DIM}$2${C_RESET}}"
}

fail() {
    N_ERR=$((N_ERR + 1))
    out "  ${C_RED}✗${C_RESET} $1${2:+ ${C_DIM}$2${C_RESET}}"
}

section() {
    flush_ok
    out ""
    out "  ${C_BOLD}${C_BLUE}▸${C_RESET} ${C_BOLD}$*${C_RESET}"
    $VERBOSE || printf '\n##### %s\n' "$*" # log marker
}

# Version of a command, an executable path, a git checkout (short HEAD) or
# py:<package>; empty when unknown. Normalised: no leading v, no trailing dot.
ver_of() {
    local v=""
    case "$1" in
    py:*) v=$(python3 -c "import importlib.metadata as m; print(m.version('${1#py:}'))" 2>/dev/null || true) ;;
    /*)
        if [[ -d "$1/.git" ]]; then
            v=$(git -C "$1" rev-parse --short HEAD 2>/dev/null || true)
        elif [[ -x "$1" ]]; then
            v=$(cmd_version "$1")
        fi
        ;;
    *) if cmd_exists "$1"; then v=$(cmd_version "$1"); fi ;;
    esac
    printf '%s' "$v"
}

# First of `--version`, `version --client`, `version` that prints a version
# (stdout or stderr: some tools, e.g. cliphist, print it on stderr).
cmd_version() {
    local form v
    for form in "--version" "version --client" "version"; do
        # shellcheck disable=SC2086 # split the form into arguments
        v=$("$1" $form 2>&1 </dev/null |
            grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?([-+.][0-9A-Za-z.+-]+)?' | head -1 | sed 's/[.+-]*$//' || true)
        if [[ -n "$v" ]]; then
            printf '%s' "$v"
            return 0
        fi
    done
}

norm_ver() {
    local v=${1#v}
    printf '%s' "${v#go}"
}

# is_latest <command or path> <latest version/tag>: true when installed matches.
# Remembers the latest version for the step line ("1.2 → 1.3").
is_latest() {
    LATEST_VER=$(norm_ver "$2")
    local cur
    cur=$(ver_of "$1")
    [[ -n "$cur" && -n "$LATEST_VER" ]] || return 1
    [[ "$cur" == "$LATEST_VER" || "${cur%%+*}" == "${LATEST_VER%%+*}" ]]
}

# Fingerprint of what a step manages, to tell a real upgrade from a no-op:
# a command's binary, a file, a git checkout's HEAD, or py:<package> version.
sum_of() {
    local p
    case "$1" in
    py:*) ver_of "$1" ;;
    /*)
        if [[ -d "$1/.git" ]]; then
            git -C "$1" rev-parse HEAD 2>/dev/null || true
        elif [[ -f "$1" ]]; then
            cksum <"$1" | awk '{print $1 $2}'
        fi
        ;;
    *) p=$(command -v "$1" 2>/dev/null) && [[ -f "$p" ]] && cksum <"$p" | awk '{print $1 $2}' || true ;;
    esac
}

spinner() {
    trap 'exit 0' TERM
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 label=$STEP_LABEL
    ((${#label} > COLS - 20)) && label="${label:0:$((COLS - 21))}…"
    while :; do
        printf '\r  %s%s%s %s %s%s…%s\e[K' "$C_CYAN" "${frames[i++ % 10]}" "$C_RESET" \
            "$label" "$C_DIM" "${STEP_VERB%e}ing" "$C_RESET" >&3
        sleep 0.1
    done
}

stop_spin() {
    if [[ -n "$SPIN_PID" ]]; then
        kill "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
        SPIN_PID=""
        printf '\r\e[K' >&3
    fi
}

# Use as:  if step <label> [install|upgrade|update] [what to fingerprint]; then
#              …work…; done_step
#          fi
# Verb defaults to upgrade when the command already exists, else install.
# With --dry-run it reports what would happen and returns 1 (body skipped).
step() {
    STEP_LABEL=$1
    STEP_BIN=${3:-$1}
    if [[ -n "${2:-}" ]]; then
        STEP_VERB=$2
    elif cmd_exists "$STEP_BIN"; then
        STEP_VERB=upgrade
    else
        STEP_VERB=install
    fi
    STEP_VER=""
    if [[ "$STEP_VERB" == upgrade ]]; then STEP_VER=$(ver_of "$STEP_BIN"); fi

    if $DRY_RUN; then
        case "$STEP_VERB" in
        install)
            out "  ${C_YELLOW}+${C_RESET} $STEP_LABEL ${C_DIM}would install${LATEST_VER:+ $LATEST_VER}${C_RESET}"
            N_INSTALLED=$((N_INSTALLED + 1))
            INSTALLED_LIST+=("$STEP_LABEL${LATEST_VER:+ $LATEST_VER}")
            ;;
        upgrade)
            if [[ "$LATEST_VER" == " " ]]; then # known outdated, versions in the label
                out "  ${C_YELLOW}↑${C_RESET} $STEP_LABEL ${C_DIM}would upgrade${C_RESET}"
                N_UPGRADED=$((N_UPGRADED + 1))
                UPGRADED_LIST+=("$STEP_LABEL")
            elif [[ -n "$LATEST_VER" ]]; then
                out "  ${C_YELLOW}↑${C_RESET} $STEP_LABEL ${C_DIM}would upgrade${STEP_VER:+ $STEP_VER} → $LATEST_VER${C_RESET}"
                N_UPGRADED=$((N_UPGRADED + 1))
                UPGRADED_LIST+=("$STEP_LABEL${STEP_VER:+ $STEP_VER} → $LATEST_VER")
            else
                out "  ${C_YELLOW}?${C_RESET} $STEP_LABEL ${C_DIM}would check for a newer version${C_RESET}"
                N_MAYBE=$((N_MAYBE + 1))
                MAYBE_LIST+=("$STEP_LABEL")
            fi
            ;;
        *) out "  ${C_YELLOW}~${C_RESET} $STEP_LABEL ${C_DIM}would ${STEP_VERB}${C_RESET}" ;;
        esac
        LATEST_VER="" STEP_LABEL=""
        return 1
    fi

    STEP_SUM=""
    if [[ "$STEP_VERB" != install ]]; then STEP_SUM=$(sum_of "$STEP_BIN"); fi
    STEP_START=$SECONDS
    $VERBOSE || printf '\n=== %s: %s\n' "$STEP_VERB" "$STEP_LABEL" # log marker
    if $SPIN; then
        spinner &
        SPIN_PID=$!
    fi
}

done_step() {
    stop_spin
    local secs=$((SECONDS - STEP_START)) t="" ver="" item=$STEP_LABEL
    if ((secs)); then t=" · $(fmt_time "$secs")"; fi
    if [[ -n "$STEP_SUM" && "$(sum_of "$STEP_BIN")" == "$STEP_SUM" ]]; then
        ok "$STEP_LABEL" # ran, but nothing changed
    else
        ver=$(ver_of "$STEP_BIN")
        case "$STEP_VERB" in
        install)
            N_INSTALLED=$((N_INSTALLED + 1))
            item+="${ver:+ $ver}"
            INSTALLED_LIST+=("$item")
            out "  ${C_GREEN}✓${C_RESET} $STEP_LABEL ${C_DIM}installed${ver:+ $ver}$t${C_RESET}"
            ;;
        upgrade)
            N_UPGRADED=$((N_UPGRADED + 1))
            local change=""
            if [[ -n "$STEP_VER" && -n "$ver" && "$STEP_VER" != "$ver" ]]; then change=" $STEP_VER → $ver"; fi
            item+="$change"
            UPGRADED_LIST+=("$item")
            out "  ${C_GREEN}✓${C_RESET} $STEP_LABEL ${C_DIM}upgraded$change$t${C_RESET}"
            ;;
        *)
            out "  ${C_GREEN}✓${C_RESET} $STEP_LABEL ${C_DIM}${STEP_VERB%e}ed$t${C_RESET}"
            ;;
        esac
    fi
    if ((secs >= 3)); then STEP_TIMES+=("$secs $STEP_LABEL"); fi
    LATEST_VER="" STEP_LABEL=""
}

# Run with the real terminal attached, for prompts the user has to answer.
interactive() {
    stop_spin
    "$@" >&3 2>&4
}

notify() {
    $TTY || return 0
    ((SECONDS >= 30)) || return 0
    if [[ "$OS" == "macos" ]]; then
        osascript -e "display notification \"$1\" with title \"dotfiles\"" &>/dev/null || true
    elif cmd_exists notify-send && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        notify-send -a dotfiles dotfiles "$1" &>/dev/null || true
    fi
}

on_error() {
    local rc=$? line=$1
    # Inside a subshell / command substitution: let the main shell report.
    [[ "${BASHPID:-$$}" == "$$" ]] || exit "$rc"
    trap - ERR
    stop_spin
    out ""
    out "  ${C_RED}✗ ${STEP_LABEL:-init.sh} failed${C_RESET} ${C_DIM}(exit $rc at line $line)${C_RESET}"
    if ! $VERBOSE; then
        out ""
        # Output of the failing step only: everything after the last step marker
        tr '\r' '\n' <"$LOG" | awk '/^=== /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' |
            grep -v '^[[:space:]]*$' | tail -n 20 |
            sed "s/^/    ${C_DIM}│ /; s/\$/${C_RESET}/" >&3 || true
        out ""
        out "  Full log: $(pretty_path "$LOG")"
    fi
    notify "✗ ${STEP_LABEL:-init.sh} failed"
    exit "$rc"
}

on_exit() {
    stop_spin
    if $PICKER_ON; then
        [[ -z "$STTY_OLD" ]] || stty "$STTY_OLD" </dev/tty 2>/dev/null || true
        printf '\e[?1049l' >&3
    fi
    if [[ -n "$SUDO_PID" ]]; then kill "$SUDO_PID" 2>/dev/null || true; fi
    if $TTY; then printf '\e[?25h' >&3; fi
}

trap 'on_error $LINENO' ERR
trap on_exit EXIT
if $SPIN; then printf '\e[?25l' >&3; fi # hide the cursor while spinning

want_section() {
    [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]] && [[ ",$SKIP," != *",$1,"* ]]
}

# -----------------------------------------------------------------------------
# Apps — everything optional, grouped by where it comes from. Any app can be
# omitted (checklist, --omit-app / --add-app); the choice is saved
# and applies to install and upgrade runs. Omitted apps are never removed.
# -----------------------------------------------------------------------------
BREW_BASE=(zsh-syntax-highlighting htop wget luajit pwgen bat fd ripgrep tmux watch
    pyenv pyenv-virtualenv eza zoxide jandedobbeleer/oh-my-posh/oh-my-posh zellij node go uv
    tree-sitter-cli jq yq lazygit btop pipx p7zip nmap mtr ipcalc)
BREW_CASKS=(font-meslo-lg-nerd-font maccy rectangle)
BREW_DEVOPS=(hashicorp/tap/terraform hashicorp/tap/vault terraform-docs ansible kubernetes-cli
    derailed/k9s/k9s mysql-client@8.0 helm gh azure-cli eksctl argocd actionlint yamllint tfsec
    maven dotnet dotnet@8 deno)
# The script itself needs these, so they can't be omitted
APT_CORE=(zsh curl git unzip jq fontconfig ca-certificates gnupg procps)
APT_BASE=(zsh-syntax-highlighting htop wget bat fd-find ripgrep tmux wl-clipboard wofi wtype
    btop pipx p7zip-full nmap mtr-tiny ipcalc)
APT_DEVOPS=(terraform vault gh azure-cli ansible yamllint maven dotnet-sdk-8.0)

app_ids() {
    local p
    for p; do printf '%s ' "${p##*/}"; done
}

# One line per source: "<source>|<app> <app> …" (checklist order)
app_catalog() {
    if [[ "$OS" == "macos" ]]; then
        echo "Homebrew|$(app_sorted "${BREW_BASE[@]}" "${BREW_DEVOPS[@]}" "${BREW_CASKS[@]}" neovim)"
        echo "Vendor installers|aws claude"
        echo "Built from source|wezterm"
        echo "Git clone|fzf tpm"
        echo "npm (global)|copilot"
        echo "pip (user)|pynvim"
    else
        echo "apt|$(app_sorted "${APT_BASE[@]}" "${APT_DEVOPS[@]}" node)"
        echo "GitHub releases|$(app_sorted eza zoxide oh-my-posh zellij lazygit yq cliphist helm k9s eksctl argocd actionlint tfsec terraform-docs)"
        echo "Vendor installers|$(app_sorted go neovim kubectl aws uv pyenv deno claude font-meslo-lg-nerd-font)"
        echo "Built from source|keyd wezterm"
        echo "Git clone|fzf tpm"
        echo "npm (global)|copilot tree-sitter-cli"
        echo "pip (user)|pynvim"
    fi
}

app_sorted() {
    app_ids "$@" | tr ' ' '\n' | sed '/^$/d' | sort -f | tr '\n' ' '
}

# How an app is installed when its source alone doesn't say (checklist note)
app_note() {
    if [[ "$OS" == "macos" ]]; then
        case "$1" in
        neovim) echo "--HEAD" ;;
        aws) echo "AWS .pkg" ;;
        claude) echo "claude.ai script" ;;
        wezterm) echo "cargo, jad617 fork" ;;
        *) if [[ " ${BREW_CASKS[*]} " == *" $1 "* ]]; then echo cask; fi ;;
        esac
    else
        case "$1" in
        node) echo "NodeSource" ;;
        go) echo "go.dev tarball" ;;
        neovim) echo "nightly tarball" ;;
        kubectl) echo "dl.k8s.io" ;;
        aws) echo "AWS zip" ;;
        uv) echo "astral.sh script" ;;
        pyenv) echo "pyenv.run script" ;;
        deno) echo "deno.land script" ;;
        claude) echo "claude.ai script" ;;
        font-meslo-lg-nerd-font) echo "p10k fonts" ;;
        wezterm) echo "cargo, jad617 fork" ;;
        keyd) echo "make" ;;
        esac
    fi
}

app_source() {
    local src list
    while IFS='|' read -r src list; do
        if [[ " $list " == *" $1 "* ]]; then
            printf '%s' "$src"
            return
        fi
    done < <(app_catalog)
}

OMIT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/omitted-apps"
OMIT=""
if [[ -f "$OMIT_FILE" ]]; then
    OMIT=$(grep -v '^[[:space:]]*\(#\|$\)' "$OMIT_FILE" | tr '\n' ' ' || true)
    OMIT=$(echo $OMIT) # trim
fi

omitted() { [[ " $OMIT " == *" $1 "* ]]; }

# True when the user omitted the app; noted for the section's "omitted" line.
skip_app() {
    omitted "$1" || return 1
    SECTION_OMIT+=("$1")
}

save_omit() {
    $DRY_RUN && return 0
    mkdir -p "$(dirname "$OMIT_FILE")"
    {
        echo "# Apps init.sh doesn't install or upgrade, one per line."
        echo "# Change with ./init.sh --select, --omit-app or --add-app."
        if [[ -n "$OMIT" ]]; then printf '%s\n' $OMIT; fi
    } >"$OMIT_FILE"
}

# Join "key|what it does" hints into HINTS, fitting $width - 4 columns: optional hints
# (leading ~) go first, then any from the end. Uses pick_apps' width and colour variables.
pick_hints() {
    local hs=("$@") h len i
    while :; do
        len=0
        for h in "${hs[@]}"; do len=$((len + ${#h} + 3)); done # "|" becomes " ", plus a 3-space gap
        ((len - 3 <= width - 4 || ${#hs[@]} <= 1)) && break
        for ((i = ${#hs[@]} - 1; i >= 0; i--)); do [[ "${hs[i]}" == "~"* ]] && break; done
        ((i < 0)) && i=$((${#hs[@]} - 1))
        hs=("${hs[@]:0:i}" "${hs[@]:i+1}")
    done
    HINTS=""
    for h in "${hs[@]}"; do
        h=${h#\~}
        HINTS+="${HINTS:+   }${CY}${BD}${h%%|*}${R} ${DM}${h#*|}${R}"
    done
}

# One-line description of an app for the checklist's detail line
app_desc() {
    case "$1" in
    actionlint) echo "Lint GitHub Actions workflows" ;;
    ansible) echo "Automation and configuration management" ;;
    argocd) echo "Argo CD CLI" ;;
    aws) echo "AWS CLI v2" ;;
    azure-cli) echo "Azure CLI" ;;
    bat) echo "cat with syntax highlighting" ;;
    btop) echo "Resource monitor" ;;
    claude) echo "Claude Code CLI" ;;
    cliphist) echo "Wayland clipboard history" ;;
    copilot) echo "GitHub Copilot CLI" ;;
    deno) echo "JavaScript/TypeScript runtime" ;;
    dotnet | dotnet-sdk-8.0) echo ".NET SDK" ;;
    dotnet@8) echo ".NET 8 SDK" ;;
    eksctl) echo "Amazon EKS CLI" ;;
    eza) echo "Modern ls" ;;
    fd | fd-find) echo "Fast find" ;;
    font-meslo-lg-nerd-font) echo "MesloLG Nerd Font" ;;
    fzf) echo "Fuzzy finder" ;;
    gh) echo "GitHub CLI" ;;
    go) echo "Go toolchain" ;;
    helm) echo "Kubernetes package manager" ;;
    htop) echo "Process viewer" ;;
    ipcalc) echo "IP subnet calculator" ;;
    jq) echo "JSON processor" ;;
    k9s) echo "Kubernetes TUI" ;;
    keyd) echo "Key remapping daemon" ;;
    kubectl | kubernetes-cli) echo "Kubernetes CLI" ;;
    lazygit) echo "Git TUI" ;;
    luajit) echo "LuaJIT" ;;
    maccy) echo "Clipboard manager" ;;
    maven) echo "Java build tool" ;;
    mtr | mtr-tiny) echo "traceroute + ping" ;;
    mysql-client@8.0) echo "MySQL 8.0 client" ;;
    neovim) echo "Neovim nightly" ;;
    nmap) echo "Network scanner" ;;
    node) echo "Node.js" ;;
    oh-my-posh) echo "Prompt theme engine" ;;
    p7zip | p7zip-full) echo "7-Zip" ;;
    pipx) echo "Python app installer" ;;
    pwgen) echo "Password generator" ;;
    pyenv) echo "Python version manager" ;;
    pyenv-virtualenv) echo "pyenv virtualenv plugin" ;;
    pynvim) echo "Neovim Python client" ;;
    rectangle) echo "Window snapping" ;;
    ripgrep) echo "Fast grep" ;;
    terraform) echo "Infrastructure as code" ;;
    terraform-docs) echo "Terraform module docs" ;;
    tfsec) echo "Terraform security scanner" ;;
    tmux) echo "Terminal multiplexer" ;;
    tpm) echo "tmux plugin manager" ;;
    tree-sitter-cli) echo "Tree-sitter CLI" ;;
    uv) echo "Python package manager" ;;
    vault) echo "HashiCorp Vault CLI" ;;
    watch) echo "Re-run a command periodically" ;;
    wezterm) echo "Terminal emulator" ;;
    wget) echo "File downloader" ;;
    wl-clipboard) echo "Wayland clipboard tools" ;;
    wofi) echo "Wayland launcher" ;;
    wtype) echo "Wayland key typing" ;;
    yamllint) echo "YAML linter" ;;
    yq) echo "YAML processor" ;;
    zellij) echo "Terminal workspace" ;;
    zoxide) echo "Smarter cd" ;;
    zsh-syntax-highlighting) echo "zsh syntax highlighting" ;;
    esac
}

# Fills CL with line $2 of card $1 (title, app rows, bottom border).
# Reads pick_apps' locals.
pick_card_line() {
    local g=$1 r=$2 w=${gw[$1]} col=${gcol[$1]} t s i c p v pad cell name
    if ((r == 0)); then
        s=0
        for ((i = first[g]; i < first[g + 1]; i++)); do ((s += on[i])); done
        t="${srcs[g]} $s/$((first[g + 1] - first[g]))"
        printf -v pad '%*s' $((w - ${#t} - 5)) ''
        CL="${col}╭─ $R$BD$t$R$col ${pad// /─}╮$R"
        return 0
    fi
    if ((r == gh[g] - 1)); then
        printf -v pad '%*s' $((w - 2)) ''
        CL="${col}╰${pad// /─}╯$R"
        return 0
    fi
    CL="${col}│$R"
    # shellcheck disable=SC2206 # app ids: no spaces or globs
    va=(${vis[g]})
    for ((c = 0; c < gk[g]; c++)); do
        p=$((c * grows[g] + r - 1))
        if ((p >= ${#va[@]})); then
            printf -v pad '%*s' "${gcw[g]}" ''
            CL+=$pad
            continue
        fi
        i=${va[p]}
        name=${ids[i]}
        if [[ -n "$filt" && "$name" == *"$filt"* ]]; then
            name="${name%%"$filt"*}$YE$BD$filt$R${HL_ON}${name#*"$filt"}"
        fi
        if ((on[i])); then
            cell="${GR}●$R${HL_ON} $name"
        else
            cell="${DM}○ $ST$name$R$DM${HL_ON}"
        fi
        [[ -z "${notes[i]}" ]] || cell+=" ${DM}[${notes[i]}]$R${HL_ON}"
        printf -v pad '%*s' $((gcw[g] - 4 - len[i])) ''
        if ((i == cur)); then
            # Dark text on the light highlight: no colours, filter match underlined
            name=${ids[i]}
            if [[ -n "$filt" && "$name" == *"$filt"* ]]; then
                name="${name%%"$filt"*}"$'\e[4m'"$filt"$'\e[24m'"${name#*"$filt"}"
            fi
            if ((on[i])); then cell="● $BD$name"$'\e[22m'; else cell="○ $ST$name"$'\e[29m'; fi
            [[ -z "${notes[i]}" ]] || cell+=" [${notes[i]}]"
            CL+="${SEL}❯ $cell$pad$R"
        else
            CL+="  ${cell//"$HL_ON"/}$pad"
        fi
    done
    printf -v pad '%*s' $((w - 2 - gk[g] * gcw[g])) ''
    CL+="$pad${col}│$R"
    return 0
}

# Checklist of every app as one card per source, with a filter: unchecked =
# omitted. Returns 1 when cancelled.
pick_apps() {
    local srcs=() first=() ids=() notes=() on=() len=() src list id n=0 g
    while IFS='|' read -r src list; do
        srcs+=("$src")
        first+=("$n")
        for id in $list; do
            ids+=("$id")
            notes+=("$(app_note "$id")")
            if omitted "$id"; then on+=(0); else on+=(1); fi
            n=$((n + 1))
        done
    done < <(app_catalog)
    first+=("$n") # end of the last source
    local R=$'\e[0m' BD=$'\e[1m' DM=$'\e[2m' ST=$'\e[9m' SEL=$'\e[48;5;108m\e[38;5;235m' HL_ON=$'\x01'
    local GR=$'\e[32m' YE=$'\e[33m' CY=$'\e[36m' MG=$'\e[35m'
    local palette=($'\e[36m' $'\e[35m' $'\e[31m' $'\e[34m' $'\e[32m' $'\e[33m' $'\e[96m')
    local ng=${#srcs[@]} vis=() gk=() grows=() gcw=() gw=() gh=() gx=() gy=() gcol=() ix=() iy=() ib=() ir=()
    local specs=() bands=0 BT=0 cur=0 top=0 size="" new_size layout="" width height hv key k2 buf
    local scroll=0 filt="" typing=false nvis=0 sel i c r k w p va plain t pad x y b best bd d mw cnt
    local cg=0 bx bw bh=0 bused bcols bandw tok CL cy cx rest
    for ((i = 0; i < n; i++)); do
        len[i]=${#ids[i]}
        [[ -z "${notes[i]}" ]] || len[i]=$((len[i] + 3 + ${#notes[i]}))
    done
    for ((g = 0; g < ng; g++)); do gcol[g]=${palette[g % ${#palette[@]}]}; done
    exec 5</dev/tty
    # Ctrl-O is the tty's "discard" key: turn that off so it reaches us
    STTY_OLD=$(stty -g <&5 2>/dev/null || true)
    # Non-canonical with a 0.1s read timeout, so a lone Esc is told apart from arrow keys quickly
    stty discard undef -icanon -echo min 0 time 1 <&5 2>/dev/null || true
    PICKER_ON=true
    printf '\e[?1049h\e[?25l' >&3
    while :; do
        # Ask the terminal itself (stdout/stderr go to the log, so tput would
        # fall back to 80x24); re-read per key to follow resizes, not mid-scroll
        if ((scroll == 0)) || [[ -z "$size" ]]; then
            new_size=$(stty size <&5 2>/dev/null || echo 24 80)
        fi
        if [[ "$new_size|$filt" != "$layout" ]]; then
            layout="$new_size|$filt" size=$new_size
            height=${size% *} width=${size#* }
            hv=$((height - 9)) # header 2, ↓ line, filter 3, detail, footer 2
            ((hv < 4)) && hv=4
            # Cards: as few inner columns as fit the height, packed into
            # columns left to right, then into bands below when out of width
            specs=() BT=0 bands=0 bh=0 bx=2 bw=0 bused=0 bcols=0 bandw=$((width - 2)) nvis=0
            local bcx=() bcw=() bcb=() cardbc=()
            for ((g = 0; g < ng; g++)); do
                vis[g]=""
                cnt=0 mw=0
                for ((i = first[g]; i < first[g + 1]; i++)); do
                    if [[ -z "$filt" || "${ids[i]}" == *"$filt"* ]]; then
                        vis[g]+="$i " cnt=$((cnt + 1))
                        ((len[i] > mw)) && mw=${len[i]}
                    fi
                done
                nvis=$((nvis + cnt))
                gh[g]=0
                ((cnt)) || continue
                gcw[g]=$((mw + 6)) # "❯ ● " + name [note] + gap
                for ((k = 1; ; k++)); do
                    r=$(((cnt + k - 1) / k))
                    if ((r + 2 <= hv || k >= cnt)); then break; fi
                    if (((k + 1) * gcw[g] + 2 > bandw)); then break; fi
                done
                gk[g]=$k grows[g]=$r
                t="${srcs[g]} $((first[g + 1] - first[g]))/$((first[g + 1] - first[g]))"
                w=$((k * gcw[g] + 2))
                ((w < ${#t} + 8)) && w=$((${#t} + 8))
                gw[g]=$w gh[g]=$((r + 2))
                # Same column, a new column, or a new band
                if ((bcols > 0 && bused + gh[g] <= hv && bx + (w > bw ? w : bw) <= bandw)); then
                    gx[g]=$bx gy[g]=$((BT + bused))
                    bused=$((bused + gh[g]))
                    ((w > bw)) && bw=$w
                elif ((bcols == 0 || bx + bw + 1 + w <= bandw)); then
                    ((bcols)) && bx=$((bx + bw + 1))
                    bw=$w bused=${gh[g]} bcols=$((bcols + 1))
                    gx[g]=$bx gy[g]=$BT
                    bcx+=("$bx") bcb+=("$bands")
                else
                    # close the band: its height is its tallest column
                    BT=$((BT + bh))
                    bands=$((bands + 1)) bx=2 bw=$w bused=${gh[g]} bcols=1
                    gx[g]=$bx gy[g]=$BT bh=0
                    bcx+=("$bx") bcb+=("$bands")
                fi
                cardbc[g]=$((${#bcx[@]} - 1))
                bcw[${#bcx[@]} - 1]=$bw
                ((bused > ${bh:-0})) && bh=$bused
            done
            if ((nvis)); then BT=$((BT + bh)) bands=$((bands + 1)); fi
            # Cards in a column share its width
            for ((g = 0; g < ng; g++)); do
                if ((gh[g])); then gw[g]=${bcw[cardbc[g]]}; fi
            done
            # Per board line: "card:line:pad" or "-:-:width" for each column
            for ((y = 0; y < BT; y++)); do specs[y]=""; done
            local bstart=() bend=()
            for ((g = 0; g < ng; g++)); do
                ((gh[g])) || continue
                b=${bcb[cardbc[g]]}
                if [[ -z "${bstart[b]:-}" ]] || ((gy[g] < bstart[b])); then bstart[b]=${gy[g]}; fi
                if [[ -z "${bend[b]:-}" ]] || ((gy[g] + gh[g] > bend[b])); then bend[b]=$((gy[g] + gh[g])); fi
            done
            for ((c = 0; c < ${#bcx[@]}; c++)); do
                b=${bcb[c]}
                for ((y = bstart[b]; y < bend[b]; y++)); do
                    tok="-:-:${bcw[c]}"
                    for ((g = 0; g < ng; g++)); do
                        if ((gh[g] && cardbc[g] == c && y >= gy[g] && y < gy[g] + gh[g])); then
                            tok="$g:$((y - gy[g])):$((bcw[c] - gw[g]))"
                            break
                        fi
                    done
                    specs[y]+="$tok "
                done
            done
            # Where each visible app sits, for moving the cursor
            ix=() iy=() ib=() ir=()
            for ((g = 0; g < ng; g++)); do
                ((gh[g])) || continue
                # shellcheck disable=SC2206 # app ids: no spaces or globs
                va=(${vis[g]})
                for ((p = 0; p < ${#va[@]}; p++)); do
                    i=${va[p]}
                    ix[i]=$((gx[g] + 1 + p / grows[g] * gcw[g]))
                    iy[i]=$((gy[g] + 1 + p % grows[g]))
                    ir[i]=$((p % grows[g]))
                    ib[i]=${bcb[cardbc[g]]}
                done
            done
            # Keep the cursor on a visible app
            if ((nvis)) && [[ -z "${ix[cur]:-}" ]]; then
                for ((g = 0; g < ng; g++)); do
                    # shellcheck disable=SC2206 # app ids: no spaces or globs
                    if ((gh[g])); then va=(${vis[g]}); cur=${va[0]}; break; fi
                done
            fi
        fi

        # Scroll so the cursor (and its card's title / bottom) is in view
        if ((nvis)); then
            cy=${iy[cur]}
            for ((cg = 0; cg < ng; cg++)); do ((cur >= first[cg] && cur < first[cg + 1])) && break; done
            y=$cy
            ((ir[cur] == 0)) && y=${gy[cg]}
            ((y < top)) && top=$y
            y=$cy
            ((ir[cur] == grows[cg] - 1)) && y=$((cy + 1))
            ((y >= top + hv)) && top=$((y - hv + 1))
        fi
        ((top > BT - hv)) && top=$((BT - hv))
        ((top < 0)) && top=0

        sel=0
        for i in "${on[@]}"; do ((sel += i)); done
        buf="  $BD${CY}◆$R ${BD}Choose the apps to install$R  $DM$sel of $n selected"
        ((width < 110)) || buf+=" · unchecked apps are skipped on install and upgrade"
        buf+="$R"$'\e[K\n'
        if ((top > 0)); then buf+="  ${DM}↑ more$R"; fi
        buf+=$'\e[K\n'
        for ((y = top; y < top + hv; y++)); do
            if ((y < BT)); then
                buf+="  "
                for tok in ${specs[y]}; do
                    g=${tok%%:*} t=${tok#*:} r=${t%%:*} w=${t#*:}
                    if [[ "$g" == - ]]; then
                        printf -v pad '%*s' "$((w + 1))" ''
                        buf+=$pad
                    else
                        pick_card_line "$g" "$r"
                        printf -v pad '%*s' "$((w + 1))" ''
                        buf+="$CL$pad"
                    fi
                done
            elif ((y == 0 && nvis == 0)); then
                buf+="  ${DM}No app matches \"$filt\"$R"
            fi
            buf+=$'\e[K\n'
        done
        if ((top + hv < BT)); then buf+="  ${DM}↓ more$R"; fi
        buf+=$'\e[K\n'
        # Filter box
        w=$((width - 4))
        printf -v pad '%*s' $((w - 11)) ''
        buf+="  ${MG}╭─ $R${BD}Filter$R$MG ${pad// /─}╮$R"$'\e[K\n'
        if $typing; then
            t="$MG>$R $filt${BD}▏$R"
            plain="$filt "
        elif [[ -n "$filt" ]]; then
            t="$MG>$R $filt  ${DM}esc clears$R"
            plain="$filt  esc clears"
        else
            t="$MG>$R ${DM}/ to filter$R"
            plain="/ to filter"
        fi
        k="$nvis / $n"
        printf -v pad '%*s' $((w - 7 - ${#plain} - ${#k})) ''
        buf+="  ${MG}│$R $t$pad$DM$k$R ${MG}│$R"$'\e[K\n'
        printf -v pad '%*s' $((w - 2)) ''
        buf+="  ${MG}╰${pad// /─}╯$R"$'\e[K\n'
        # Current app
        if ((nvis)); then
            if ((on[cur])); then t="installed and upgraded"; else t="skipped: not installed or upgraded"; fi
            k=$(app_desc "${ids[cur]}")
            rest="${k:+· $k }· ${srcs[cg]}${notes[cur]:+ [${notes[cur]}]} · $t"
            k=$((width - 4 - ${#ids[cur]}))
            ((${#rest} > k)) && rest="${rest:0:k-1}…"
            buf+="  $CY${ids[cur]}$R $DM$rest$R"
        fi
        # Key hints: "key|what it does"; a leading ~ marks hints dropped first when narrow
        if $typing; then
            pick_hints "a-z|filter by name" "⌫|delete" "⏎|done typing" "esc|clear filter"
            buf+=$'\e[K\n'"  $HINTS"
            pick_hints "↑↓←→|move" "space|select / skip" "^D|quit, don't save"
        else
            if [[ -n "$filt" ]]; then
                pick_hints "space|select / skip" "~s|whole card" "~a n|all / none shown" "/|edit filter" "esc|clear filter"
            else
                pick_hints "space|select / skip" "~s|whole card" "~a n|all / none" "/|filter by name"
            fi
            buf+=$'\e[K\n'"  $HINTS"
            pick_hints "hjkl ↑↓←→|move" "~tab|next card" "~^P ^O|scroll" "⏎|save & continue" "q|quit, don't save"
        fi
        buf+=$'\e[K\n'"  $HINTS"$'\e[K'
        printf '\e[H%s\e[J' "$buf" >&3

        # Ctrl-P / Ctrl-O scroll like the Neovim config: 10 rows, one per 16ms
        if ((scroll > 0)); then
            sleep 0.016
            key=j scroll=$((scroll - 1))
        elif ((scroll < 0)); then
            sleep 0.016
            key=k scroll=$((scroll + 1))
        else
            IFS= read -rsn1 key <&5 || key=$'\x04'
        fi
        if [[ "$key" == $'\e' ]]; then
            k2=$(dd bs=8 count=1 <&5 2>/dev/null) || k2=""
            key+=$k2
        fi
        # While typing a filter, letters go to the filter
        if $typing; then
            case "$key" in
            [A-Za-z0-9@._-])
                case "$key" in [A-Z]) key=$(printf '%s' "$key" | tr 'A-Z' 'a-z') ;; esac
                filt+=$key
                continue
                ;;
            $'\x7f' | $'\b')
                filt=${filt%?}
                continue
                ;;
            '')
                typing=false
                continue
                ;;
            $'\e')
                filt="" typing=false
                continue
                ;;
            esac
        fi
        cx=${ix[cur]:-0} cy=${iy[cur]:-0}
        case "$key" in
        $'\e[A' | k | $'\e[B' | j | $'\e[C' | l | $'\e[D' | h)
            ((nvis)) || continue
            best=-1 bd=999999
            for ((i = 0; i < n; i++)); do
                [[ -n "${ix[i]:-}" ]] || continue
                x=${ix[i]} y=${iy[i]} d=-1
                case "$key" in
                $'\e[B' | j)
                    if ((x == cx && y > cy)); then d=$((y - cy)); elif ((ib[i] == ib[cur] + 1)); then
                        d=$(((x > cx ? x - cx : cx - x) * 1000 + y + 100000))
                    fi
                    ;;
                $'\e[A' | k)
                    if ((x == cx && y < cy)); then d=$((cy - y)); elif ((ib[i] == ib[cur] - 1)); then
                        d=$(((x > cx ? x - cx : cx - x) * 1000 + (BT - y) + 100000))
                    fi
                    ;;
                $'\e[C' | l)
                    if ((ib[i] == ib[cur] && x > cx)); then d=$(((x - cx) * 1000 + (y > cy ? y - cy : cy - y))); elif ((ib[i] == ib[cur] + 1)); then
                        d=$((x * 1000 + y + 500000))
                    fi
                    ;;
                *)
                    if ((ib[i] == ib[cur] && x < cx)); then d=$(((cx - x) * 1000 + (y > cy ? y - cy : cy - y))); elif ((ib[i] == ib[cur] - 1)); then
                        d=$(((width - x) * 1000 + (BT - y) + 500000))
                    fi
                    ;;
                esac
                if ((d >= 0 && d < bd)); then bd=$d best=$i; fi
            done
            if ((best >= 0)); then cur=$best; else scroll=0; fi # stop at the edges
            ;;
        $'\x10') scroll=10 ;;  # Ctrl-P
        $'\x0f') scroll=-10 ;; # Ctrl-O
        $'\t' | $'\e[Z')
            ((nvis)) || continue
            for ((g = 0; g < ng; g++)); do ((cur >= first[g] && cur < first[g + 1])) && break; done
            for ((k = 1; k <= ng; k++)); do
                if [[ "$key" == $'\t' ]]; then b=$(((g + k) % ng)); else b=$(((g + ng - k) % ng)); fi
                # shellcheck disable=SC2206 # app ids: no spaces or globs
                if ((gh[b])); then va=(${vis[b]}); cur=${va[0]}; break; fi
            done
            ;;
        s)
            ((nvis)) || continue
            for ((g = 0; g < ng; g++)); do ((cur >= first[g] && cur < first[g + 1])) && break; done
            k=1
            for i in ${vis[g]}; do ((on[i])) || k=0; done
            for i in ${vis[g]}; do on[i]=$((1 - k)); done
            ;;
        ' ') if ((nvis)); then on[cur]=$((1 - on[cur])); fi ;;
        a | n)
            [[ "$key" == a ]] && k=1 || k=0
            for ((g = 0; g < ng; g++)); do for i in ${vis[g]}; do on[i]=$k; done; done
            ;;
        /) typing=true ;;
        '') break ;;
        $'\e') filt="" ;;
        esac
        if [[ "$key" == q || "$key" == Q || "$key" == $'\x04' ]]; then # Ctrl-D cancels too
            [[ -z "$STTY_OLD" ]] || stty "$STTY_OLD" <&5 2>/dev/null || true
            printf '\e[?1049l' >&3
            PICKER_ON=false
            exec 5<&-
            return 1
        fi
    done
    [[ -z "$STTY_OLD" ]] || stty "$STTY_OLD" <&5 2>/dev/null || true
    printf '\e[?1049l' >&3
    PICKER_ON=false
    exec 5<&-
    # Keep saved apps this OS doesn't know (e.g. from the other OS)
    local keep="" all=" ${ids[*]} "
    for id in $OMIT; do [[ "$all" == *" $id "* ]] || keep+=" $id"; done
    for ((i = 0; i < n; i++)); do ((on[i])) || keep+=" ${ids[i]}"; done
    OMIT=$(echo $keep)
}

if ! $DOCTOR; then
    if [[ -n "$OMIT_ADD$OMIT_DEL" ]]; then
        known=" $(app_catalog | cut -d'|' -f2 | tr '\n' ' ') "
        for a in ${OMIT_ADD//,/ } ${OMIT_DEL//,/ }; do
            [[ "$known" == *" $a "* ]] || {
                out "Unknown app: $a"
                out ""
                out "Apps on $OS_NAME, by source:"
                while IFS='|' read -r src list; do
                    wrap "      " "  $src: $list" >&3
                done < <(app_catalog)
                exit 1
            }
        done
        for a in ${OMIT_ADD//,/ }; do omitted "$a" || OMIT+=" $a"; done
        new=""
        for a in $OMIT; do [[ ",$OMIT_DEL," == *",$a,"* ]] || new+=" $a"; done
        OMIT=$(echo $new)
        save_omit
    fi
    # Every interactive run starts with the checklist (pre-set from the saved
    # choices); --yes, CI, --dry-run and --omit-app/--add-app skip it
    if $SELECT || { [[ -z "$OMIT_ADD$OMIT_DEL" && -z "${CI:-}" ]] && ! $DRY_RUN && ! $ASSUME_YES; }; then
        if $TTY && [[ -t 0 ]]; then
            if pick_apps; then
                save_omit
                if $SELECT; then
                    out "  Saved — omitting: ${OMIT:-nothing}"
                    exit 0
                fi
            else
                out "  Cancelled — nothing changed"
                exit 0
            fi
            if $SPIN; then printf '\e[?25l' >&3; else printf '\e[?25h' >&3; fi
        elif $SELECT; then
            out "--select needs an interactive terminal; use --omit-app / --add-app instead"
            exit 1
        fi
    fi
fi

# Summary rows: what's omitted and how to bring it back
omit_rows() {
    local G=$1 items=() a
    if [[ -z "$OMIT" ]]; then
        panel_row "$G" "Apps" "${C_CYAN}./init.sh --select${C_RESET} ${C_DIM}to opt out of apps without running the install${C_RESET}"
        return
    fi
    local note
    for a in $OMIT; do
        note=$(app_note "$a")
        items+=("$a ${C_DIM}($(app_source "$a")${note:+ [$note]})${C_RESET}")
    done
    panel_row "$G" "Omitted" "$(join ", " "${items[@]}")"
    panel_row "$G" "Add back" "${C_CYAN}./init.sh --add-app $(join , $OMIT)${C_RESET} ${C_DIM}or pick again:${C_RESET} ${C_CYAN}./init.sh --select${C_RESET}"
}

# -----------------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------------
out ""
out "  ${C_BLUE}╭─${C_RESET} ${C_BOLD}dotfiles bootstrap${C_RESET}"
panel_row "${C_BLUE}│ ${C_RESET}" "Supported" "${C_DIM}macOS · Ubuntu (incl. Pop!_OS) · x86_64, arm64${C_RESET}"
panel_row "${C_BLUE}│ ${C_RESET}" "Found" "${C_BOLD}$OS_NAME${C_RESET} ${C_DIM}· $UARCH${C_RESET}"
case "$MODE" in
doctor) panel_row "${C_BLUE}│ ${C_RESET}" "Mode" "${C_BOLD}doctor${C_RESET} ${C_DIM}— check the setup, change nothing${C_RESET}" ;;
upgrade) panel_row "${C_BLUE}│ ${C_RESET}" "Mode" "${C_BOLD}upgrade${C_RESET} ${C_DIM}— install what's missing, upgrade the rest${C_RESET}" ;;
install) panel_row "${C_BLUE}│ ${C_RESET}" "Mode" "${C_BOLD}install${C_RESET} ${C_DIM}— install what's missing, upgrade nothing${C_RESET}" ;;
esac
if $DRY_RUN && ! $DOCTOR; then
    panel_row "${C_BLUE}│ ${C_RESET}" "Dry run" "${C_YELLOW}showing what would change — nothing is touched${C_RESET}"
fi
if [[ -n "$ONLY$SKIP" ]] && ! $DOCTOR; then
    sel=""
    for s in $SECTIONS; do want_section "$s" && sel+="${sel:+, }$s"; done
    panel_row "${C_BLUE}│ ${C_RESET}" "Sections" "${sel:-none}"
fi
if [[ -n "$OMIT" ]] && ! $DOCTOR; then
    panel_row "${C_BLUE}│ ${C_RESET}" "Omitting" "${OMIT// /, } ${C_DIM}(--add-app or --select to change)${C_RESET}"
fi
if $VERBOSE; then
    panel_row "${C_BLUE}╰─${C_RESET}" "Output" "${C_DIM}verbose${C_RESET}"
else
    panel_row "${C_BLUE}╰─${C_RESET}" "Log" "${C_DIM}$(pretty_path "$LOG")${C_RESET}"
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
# Symlinks are declared once (src relative to the repo | destination) and used
# by both the installer and --doctor.
links() {
    cat <<EOF
shell/zsh/my_aliases.sh|$HOME/.my_aliases.sh
terminal/wezterm/wezterm.lua|$HOME/.wezterm.lua
editors/nvim|$HOME/.config/nvim
shell/prompt/ohmyposh|$HOME/.config/ohmyposh
terminal/zellij|$HOME/.config/zellij
terminal/kitty|$HOME/.config/kitty
shell/zsh/zshrc|$HOME/.zshrc
EOF
    if [[ "$OS" == "macos" ]]; then
        cat <<EOF
terminal/tmux/macos_tmux.conf|$HOME/.tmux.conf
mac/capslock.plist|$HOME/Library/LaunchAgents/com.user.capslock.plist
EOF
    else
        cat <<EOF
terminal/tmux/tmux.conf|$HOME/.tmux.conf
linux/wofi/config|$HOME/.config/wofi/config
linux/wofi/style.css|$HOME/.config/wofi/style.css
linux/autostart/cliphist-daemon.desktop|$HOME/.config/autostart/cliphist-daemon.desktop
linux/bin/clipboard-picker|$HOME/bin/clipboard-picker
EOF
    fi
}

symlink() {
    local src=$1 dst=$2
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        LINKS_OK=$((LINKS_OK + 1))
        return
    fi
    if $DRY_RUN; then
        out "  ${C_YELLOW}+${C_RESET} $(pretty_path "$dst") ${C_DIM}would link${C_RESET}"
        return
    fi
    mkdir -p "$(dirname "$dst")"
    # Remove dst unconditionally — ln -sf creates inside an existing
    # directory (real or symlink-to-dir) rather than replacing it.
    rm -rf "$dst"
    ln -s "$src" "$dst"
    out "  ${C_GREEN}✓${C_RESET} $(pretty_path "$dst") ${C_DIM}linked${C_RESET}"
}

# Login shell from the user database ($SHELL is only what this session started with).
login_shell() {
    if [[ "$OS" == "macos" ]]; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$USER" | cut -d: -f7
    fi
}

# Want a tool (re)installed: it's missing, or we're upgrading.
want() { ! cmd_exists "$1" || $UPGRADE; }

# GitHub API token, so release lookups don't hit the 60/hour anonymous limit:
# $GITHUB_TOKEN (CI), else the gh CLI's login.
GH_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    GH_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
elif cmd_exists gh && gh_token=$(gh auth token 2>/dev/null) && [[ -n "$gh_token" ]]; then
    GH_AUTH=(-H "Authorization: Bearer $gh_token")
fi

gh_api() { curl -fsSL ${GH_AUTH[@]+"${GH_AUTH[@]}"} "https://api.github.com/$1"; }

# Latest release tag of a GitHub repo, e.g. gh_latest jesseduffield/lazygit → v0.55.1
gh_latest() {
    gh_api "repos/$1/releases/latest" | jq -er '.tag_name' || {
        echo "Could not get the latest release of $1 (GitHub API rate limit?)" >&2
        return 1
    }
}

# Non-interactive apt: no debconf prompts, keep local config files on upgrade,
# and wait for the dpkg lock (unattended-upgrades often holds it after boot).
apt_get() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o DPkg::Lock::Timeout=120 \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

apt_refresh() {
    if ! $DRY_RUN && step "apt package lists" update; then
        apt_get update
        done_step
    fi
}

# Upstream part of a Debian version: 1:2.43.0-1ubuntu7.4 → 2.43.0
deb_ver() {
    local v=${1#*:}
    printf '%s' "${v%%-*}"
}

# apt: install only the missing packages (plain `apt install` would also
# upgrade installed ones); in upgrade mode also upgrade the outdated ones.
apt_install() {
    local missing=() outdated=() changes=() p line upgradable="" keep=()
    for p in "$@"; do skip_app "$p" || keep+=("$p"); done
    ((${#keep[@]})) || return 0
    set -- "${keep[@]}"
    for p in "$@"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
    done
    if $UPGRADE; then
        upgradable=$(apt list --upgradable 2>/dev/null)
        for p in "$@"; do
            # gh/stable 2.103.3 amd64 [upgradable from: 2.45.0-1ubuntu0.3]
            line=$(grep "^$p/" <<<"$upgradable" | head -n 1 || true)
            if [[ -n "$line" ]]; then
                outdated+=("$p")
                changes+=("$p $(deb_ver "$(sed 's/.*from: \(.*\)\]/\1/' <<<"$line")") → $(deb_ver "$(awk '{print $2}' <<<"$line")")")
            fi
        done
    fi
    if ((${#missing[@]})) && step "apt: ${missing[*]}" install; then
        apt_get install "${missing[@]}"
        done_step
    fi
    if ((${#outdated[@]})); then
        LATEST_VER=" " # versions are in the label
        if step "apt: $(join ", " "${changes[@]}")" upgrade; then
            apt_get install --only-upgrade "${outdated[@]}"
            done_step
        fi
    fi
    local current=$(($# - ${#missing[@]} - ${#outdated[@]}))
    if ((current > 3)); then
        ok "$current apt packages"
    elif ((current)); then
        for p in "$@"; do
            [[ " ${missing[*]} ${outdated[*]} " == *" $p "* ]] || ok "$p"
        done
    fi
}

# Third-party apt repo. The signing key is re-fetched every run: vendors rotate
# keys (HashiCorp did in 2026) and a stale keyring silently freezes the repo.
# apt update only runs when the key or the source line actually changed.
# Usage: apt_repo <list name> <key url> <source line with signed-by=keyring>
apt_repo() {
    local list="/etc/apt/sources.list.d/$1.list" key_url=$2 line=$3
    local keyring=${line#*signed-by=}
    keyring=${keyring%%[] ]*}
    local tmp key_changed=false list_changed=false
    tmp=$(mktemp)
    curl -fsSL "$key_url" | gpg --batch --yes --dearmor -o "$tmp"
    cmp -s "$tmp" "$keyring" || key_changed=true
    [[ "$(cat "$list" 2>/dev/null)" == "$line" ]] || list_changed=true
    if { $key_changed || $list_changed; } && step "$1 apt repo" "$($list_changed && echo install || echo update)"; then
        sudo install -m 644 "$tmp" "$keyring"
        echo "$line" | sudo tee "$list" >/dev/null
        apt_get update
        done_step
    fi
    rm -f "$tmp"
}

# Homebrew: install only what's missing (`brew install` would upgrade or
# complain about installed ones); in upgrade mode also upgrade the outdated
# ones (casks with --greedy, so self-updating / nightly casks are included).
# Names must be canonical (no aliases), e.g. kubernetes-cli not kubectl.
brew_install() {
    local kind=--formula greedy=()
    if [[ "$1" == --cask ]]; then
        kind=--cask greedy=(--greedy)
        shift
    fi
    local keep=() p
    for p in "$@"; do skip_app "${p##*/}" || keep+=("$p"); done
    ((${#keep[@]})) || return 0
    set -- "${keep[@]}"
    local installed missing=() present=() outdated=() p
    installed=$(brew list "$kind" -1)
    for p in "$@"; do
        if grep -qx "${p##*/}" <<<"$installed"; then present+=("$p"); else missing+=("$p"); fi
    done
    if $UPGRADE && ((${#present[@]})); then
        while IFS= read -r p; do
            [[ -n "$p" ]] && outdated+=("$p")
        done < <(brew outdated "$kind" ${greedy[@]+"${greedy[@]}"} --quiet "${present[@]}" 2>/dev/null || true)
    fi
    if ((${#missing[@]})) && step "brew: ${missing[*]##*/}" install; then
        brew install "$kind" "${missing[@]}"
        done_step
    fi
    if ((${#outdated[@]})); then
        LATEST_VER=" " # outdated per brew
        if step "brew: ${outdated[*]##*/}" upgrade; then
            brew upgrade "$kind" ${greedy[@]+"${greedy[@]}"} "${outdated[@]}"
            done_step
        fi
    fi
    local current=$((${#present[@]} - ${#outdated[@]}))
    if ((current)); then ok "$current brew ${kind#--}s"; fi
}

# Install / upgrade a single binary from a URL into /usr/local/bin.
install_bin() {
    local name=$1 url=$2
    sudo curl -fsSL "$url" -o "/usr/local/bin/$name"
    sudo chmod +x "/usr/local/bin/$name"
}

# Install a binary from a GitHub release tarball into /usr/local/bin.
# install_tar_bin <name> <url> [path inside the archive]
install_tar_bin() {
    local name=$1 url=$2 member=${3:-$1} tmp
    tmp=$(mktemp -d)
    curl -fsSL "$url" | tar -xz -C "$tmp"
    sudo install "$tmp/$member" "/usr/local/bin/$name"
    rm -rf "$tmp"
}

# GitHub-release tool: skip when already at the latest release (upgrade mode
# only re-downloads what's outdated).
# gh_tool <command> <owner/repo> <function that installs it, given the tag>
gh_tool() {
    local cmd=$1 repo=$2 fn=$3 tag=""
    if skip_app "$cmd"; then return; fi
    if ! want "$cmd"; then
        ok "$cmd"
        return
    fi
    tag=$(gh_latest "$repo")
    if is_latest "$cmd" "$tag"; then
        ok "$cmd"
        LATEST_VER=""
        return
    fi
    if step "$cmd"; then
        "$fn" "$tag"
        done_step
    fi
}

# Global npm package (Linux: NodeSource's npm in /usr, needs sudo).
npm_global() {
    local bin=$1 pkg=$2
    if skip_app "${pkg##*/}"; then return 0; fi
    if omitted node && ! cmd_exists npm; then
        warn "$bin" "skipped — needs node, which is omitted"
        return 0
    fi
    if ! want "$bin"; then
        ok "$bin"
        return 0
    fi
    if cmd_exists "$bin" && is_latest "$bin" "$(npm view "$pkg" version 2>/dev/null || true)"; then
        ok "$bin"
        LATEST_VER=""
        return 0
    fi
    if step "$bin"; then
        if [[ "$OS" == "macos" ]]; then npm install -g "$pkg@latest"; else sudo /usr/bin/npm install -g "$pkg@latest"; fi
        done_step
    fi
}

# -----------------------------------------------------------------------------
# fzf — git checkout in ~/.fzf + its own installer (same on both OS), which
# generates ~/.fzf.zsh sourced by zshrc. Not brew/apt, to match existing setups.
# -----------------------------------------------------------------------------
install_fzf() {
    local flags=(--key-bindings --completion --no-update-rc --no-fish)
    if skip_app fzf; then
        return
    elif [[ ! -d "$HOME/.fzf" ]]; then
        if step fzf install "$HOME/.fzf/bin/fzf"; then
            git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
            "$HOME/.fzf/install" "${flags[@]}"
            done_step
        fi
    elif $UPGRADE; then
        if step fzf upgrade "$HOME/.fzf/bin/fzf"; then
            git -C "$HOME/.fzf" pull --ff-only
            "$HOME/.fzf/install" "${flags[@]}"
            done_step
        fi
    else
        ok fzf
    fi
}

# -----------------------------------------------------------------------------
# Go — official tarball (Linux; macOS uses brew)
# -----------------------------------------------------------------------------
install_go() {
    local go_bin="/usr/local/go/bin/go"
    if skip_app go; then return; fi
    if [[ -x "$go_bin" ]] && ! $UPGRADE; then
        ok go
        return
    fi

    local latest
    latest=$(curl -fsSL "https://go.dev/dl/?mode=json" | jq -r '.[0].version')
    if is_latest "$go_bin" "$latest"; then
        ok go
        LATEST_VER=""
        return
    fi

    if step go "$([[ -x "$go_bin" ]] && echo upgrade || echo install)" "$go_bin"; then
        local archive="${latest}.linux-${ARCH}.tar.gz"
        curl -fsSL "https://go.dev/dl/${archive}" -o "/tmp/${archive}"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "/tmp/${archive}"
        rm "/tmp/${archive}"
        done_step
    fi
}

# -----------------------------------------------------------------------------
# WezTerm with per-split floating panes — built from the jad617/wezterm fork
# with cargo into ~/.local/bin, then packaged the way upstream's ci/deploy.sh
# does it (WezTerm.app on macOS, desktop entry + icon on Linux) from the
# assets in cargo's checkout of the same commit. Replaces the brew cask / apt
# package. Skipped when cargo already built the branch's current commit.
# -----------------------------------------------------------------------------
WEZTERM_REPO=https://github.com/jad617/wezterm
WEZTERM_BRANCH=floating-splits
WEZTERM_BINS=(wezterm wezterm-gui wezterm-mux-server)
WEZTERM_STAMP="$HOME/.local/share/wezterm/fork-assets-rev"
# Highest rust-version among the fork's locked dependencies (fixed 1.31.0).
# Raise it when the fork's Cargo.lock moves to crates that need a newer rustc.
WEZTERM_RUST_MIN=1.93

# Version of rustup's stable toolchain, e.g. 1.93.0 (empty if not installed)
rust_stable_ver() {
    "$HOME/.cargo/bin/rustc" +stable --version 2>/dev/null | awk '{print $2}' || true
}

# version_ge A B: true when dotted version A >= B (missing parts count as 0)
version_ge() {
    local IFS=. i a b
    # shellcheck disable=SC2206
    a=($1) b=($2)
    [[ -n "$1" ]] || return 1
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        ((10#${a[i]:-0} > 10#${b[i]:-0})) && return 0
        ((10#${a[i]:-0} < 10#${b[i]:-0})) && return 1
    done
    return 0
}

# Commit of the fork that cargo last built into ~/.local, from its install record
wezterm_built_rev() {
    jq -r --arg src "(git+$WEZTERM_REPO?branch=$WEZTERM_BRANCH#" '
        .installs | keys[] | select(startswith("wezterm-gui ") and contains($src))
        | sub(".*#"; "") | rtrimstr(")")' "$HOME/.local/.crates2.json" 2>/dev/null | head -n 1 || true
}

install_wezterm_fork() {
    local gui="$HOME/.local/bin/wezterm-gui" built head
    if skip_app wezterm; then return 0; fi
    built=$(wezterm_built_rev)

    if [[ -n "$built" && -x "$gui" ]] && ! $UPGRADE; then
        ok "wezterm (floating panes)"
    elif ! head=$(git ls-remote "$WEZTERM_REPO" "refs/heads/$WEZTERM_BRANCH" | cut -f1) || [[ -z "$head" ]]; then
        warn "wezterm (floating panes)" "branch $WEZTERM_BRANCH not found on $WEZTERM_REPO"
        return 0
    elif [[ "$built" == "$head" && -x "$gui" ]]; then
        ok "wezterm (floating panes)"
    else
        # rustup's toolchain: distro cargo can be too old for WezTerm
        if [[ ! -x "$HOME/.cargo/bin/cargo" ]] && step rustup install "$HOME/.cargo/bin/cargo"; then
            curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs |
                sh -s -- -y --no-modify-path --profile minimal
            done_step
        # rustup never updates on its own: bring stable up to the fork's
        # minimum Rust, and leave a newer toolchain alone.
        elif [[ -x "$HOME/.cargo/bin/rustup" ]] && ! version_ge "$(rust_stable_ver)" "$WEZTERM_RUST_MIN"; then
            LATEST_VER=">= $WEZTERM_RUST_MIN"
            if step "rust stable" upgrade "$HOME/.cargo/bin/rustc"; then
                "$HOME/.cargo/bin/rustup" update stable --no-self-update
                done_step
            fi
        fi
        if [[ -x "$HOME/.cargo/bin/rustup" ]] && ! $DRY_RUN &&
            ! version_ge "$(rust_stable_ver)" "$WEZTERM_RUST_MIN"; then
            warn "wezterm (floating panes)" "needs rustc >= $WEZTERM_RUST_MIN, stable is $(rust_stable_ver)"
            return 0
        fi

        # Build dependencies, as listed by the fork's get-deps (macOS: the
        # Xcode command line tools that Homebrew already needs)
        if [[ "$OS" != "macos" ]]; then
            apt_install cmake gcc g++ pkg-config libegl1-mesa-dev libssl-dev \
                libfontconfig1-dev libwayland-dev libx11-xcb-dev libxcb-ewmh-dev \
                libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev libxcb-randr0-dev \
                libxcb-render0-dev libxcb-xkb-dev libxcb-util-dev libxkbcommon-dev \
                libxkbcommon-x11-dev xorg-dev
        fi

        LATEST_VER=${head:0:9}
        if step "wezterm (floating panes)" "$([[ -x "$gui" ]] && echo upgrade || echo install)" "$gui"; then
            # --force: replaces binaries cargo didn't install (e.g. a manual build).
            # An explicit target dir: wezterm-gui's build.rs (macOS) copies
            # Info.plist into $CARGO_TARGET_DIR, else into <checkout>/target/<profile>,
            # which doesn't exist under `cargo install`.
            local target
            target=$(mktemp -d)
            CARGO_TARGET_DIR=$target "$HOME/.cargo/bin/cargo" +stable install --locked --force --root "$HOME/.local" \
                --git "$WEZTERM_REPO" --branch "$WEZTERM_BRANCH" "${WEZTERM_BINS[@]}"
            rm -rf "$target"
            done_step
        fi
    fi

    [[ -x "$gui" ]] || return 0
    wezterm_drop_package
    if [[ "$OS" == "macos" ]]; then wezterm_macos_app; else wezterm_linux_assets; fi
}

# The fork's source tree for the built commit: cargo's git checkout, or a
# shallow fetch of that commit when cargo has garbage-collected it. Sets
# WEZTERM_SRC (and WEZTERM_SRC_TMP, for the caller to remove, on a fetch).
wezterm_fork_src() {
    local rev=$1 d
    WEZTERM_SRC="" WEZTERM_SRC_TMP=""
    for d in "$HOME"/.cargo/git/checkouts/wezterm-*/"${rev:0:7}"*; do
        if [[ -f "$d/assets/wezterm.desktop" ]]; then
            WEZTERM_SRC=$d
            return 0
        fi
    done
    WEZTERM_SRC_TMP=$(mktemp -d)
    git -C "$WEZTERM_SRC_TMP" init -q &&
        git -C "$WEZTERM_SRC_TMP" fetch -q --depth 1 "$WEZTERM_REPO" "$rev" &&
        git -C "$WEZTERM_SRC_TMP" checkout -q FETCH_HEAD -- assets termwiz/data/wezterm.terminfo &&
        WEZTERM_SRC=$WEZTERM_SRC_TMP
}

# Remove the packaged WezTerm (brew cask / apt nightly) once the fork build
# exists, so a package upgrade can't swap the stock build back in
wezterm_drop_package() {
    if [[ "$OS" == "macos" ]]; then
        local casks
        casks=$(brew list --cask -1 2>/dev/null | grep -xE 'wezterm(@nightly)?' | tr '\n' ' ' || true)
        if [[ -n "$casks" ]] && step "brew: ${casks% }" remove /Applications/WezTerm.app/Contents/MacOS/wezterm-gui; then
            # shellcheck disable=SC2086 # one word per cask
            brew uninstall --cask $casks
            done_step
        fi
    else
        if dpkg -s wezterm-nightly >/dev/null 2>&1 && step "apt: wezterm-nightly" remove /usr/bin/wezterm; then
            sudo apt-get remove -y wezterm-nightly
            sudo rm -f /etc/apt/sources.list.d/wezterm.list /usr/share/keyrings/wezterm-fury.gpg
            done_step
        fi
    fi
}

# /Applications/WezTerm.app assembled like ci/deploy.sh: the bundle template,
# shell integration and completions, compiled terminfo and the fork binaries,
# ad-hoc signed. Built beside the old app and moved into place, so a running
# WezTerm keeps its (now unlinked) files.
wezterm_macos_app() {
    local app=/Applications/WezTerm.app new=/Applications/.WezTerm.app.new bin res sums
    # codesign rewrites the bundled binaries, so compare checksums of
    # ~/.local/bin recorded at packaging time instead of the files themselves
    sums=$(cd "$HOME/.local/bin" && shasum "${WEZTERM_BINS[@]}")
    if [[ -d "$app/Contents/Resources/terminfo" &&
        "$(cat "$app/Contents/Resources/fork-bins.sha" 2>/dev/null || true)" == "$sums" ]]; then
        ok "WezTerm.app"
        return 0
    fi
    if [[ ! -w /Applications ]] && ! $DRY_RUN; then
        warn "WezTerm.app" "/Applications isn't writable (needs admin rights) — rerun ./init.sh as an admin"
        return 0
    fi
    if step "WezTerm.app" "$([[ -d "$app" ]] && echo update || echo install)" "$app/Contents/MacOS/wezterm-gui"; then
        wezterm_fork_src "$(wezterm_built_rev)"
        rm -rf "$new"
        cp -R "$WEZTERM_SRC/assets/macos/WezTerm.app" "$new"
        # Upstream omits the bundled MetalANGLE libraries too
        rm -f "$new"/*.dylib
        res="$new/Contents/Resources"
        mkdir -p "$new/Contents/MacOS" "$res"
        cp -R "$WEZTERM_SRC"/assets/shell-integration/* "$res"
        cp -R "$WEZTERM_SRC/assets/shell-completion" "$res"
        tic -xe wezterm -o "$res/terminfo" "$WEZTERM_SRC/termwiz/data/wezterm.terminfo"
        for bin in "${WEZTERM_BINS[@]}"; do
            cp "$HOME/.local/bin/$bin" "$new/Contents/MacOS/$bin"
        done
        printf '%s\n' "$sums" >"$res/fork-bins.sha"
        codesign --force --deep --sign - "$new"
        rm -rf "$app.old"
        if [[ -e "$app" ]]; then mv "$app" "$app.old"; fi
        mv "$new" "$app"
        rm -rf "$app.old"
        [[ -z "$WEZTERM_SRC_TMP" ]] || rm -rf "$WEZTERM_SRC_TMP"
        done_step
    fi
}

# What the .deb ships, user-level: desktop entry (running ~/.local/bin), icon,
# zsh completion and terminfo. Redone whenever the built commit changes.
wezterm_linux_assets() {
    local rev apps="$HOME/.local/share/applications" icons="$HOME/.local/share/icons/hicolor/128x128/apps"
    rev=$(wezterm_built_rev)
    if [[ -f "$WEZTERM_STAMP" && "$(cat "$WEZTERM_STAMP")" == "$rev" ]]; then
        ok "wezterm launcher"
        return 0
    fi
    if step "wezterm launcher" "$([[ -f "$WEZTERM_STAMP" ]] && echo update || echo install)" "$apps/org.wezfurlong.wezterm.desktop"; then
        wezterm_fork_src "$rev"
        mkdir -p "$apps" "$icons" "$HOME/.zfunc" "$(dirname "$WEZTERM_STAMP")"
        sed -e "s|^TryExec=wezterm\$|TryExec=$HOME/.local/bin/wezterm|" \
            -e "s|^Exec=wezterm |Exec=$HOME/.local/bin/wezterm |" \
            "$WEZTERM_SRC/assets/wezterm.desktop" >"$apps/org.wezfurlong.wezterm.desktop"
        cp "$WEZTERM_SRC/assets/icon/terminal.png" "$icons/org.wezfurlong.wezterm.png"
        cp "$WEZTERM_SRC/assets/shell-completion/zsh" "$HOME/.zfunc/_wezterm"
        tic -x -o "$HOME/.terminfo" "$WEZTERM_SRC/termwiz/data/wezterm.terminfo"
        [[ -z "$WEZTERM_SRC_TMP" ]] || rm -rf "$WEZTERM_SRC_TMP"
        printf '%s\n' "$rev" >"$WEZTERM_STAMP"
        done_step
    fi
}

# =============================================================================
# macOS — base tools
# =============================================================================
install_macos() {
    section "Base packages"

    if ! cmd_exists brew; then
        if $DRY_RUN; then
            out "  ${C_YELLOW}+${C_RESET} Homebrew ${C_DIM}would install — rest of this section needs it${C_RESET}"
            return
        fi
        out "  ${C_DIM}Installing Homebrew (may ask for your password)${C_RESET}"
        interactive /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    brew_install "${BREW_BASE[@]}"

    # Rectangle installed outside brew is left alone
    local casks=() c
    for c in "${BREW_CASKS[@]}"; do
        [[ "$c" == rectangle && -d /Applications/Rectangle.app ]] || casks+=("$c")
    done
    brew_install --cask "${casks[@]}"

    install_wezterm_fork

    install_fzf
}

# =============================================================================
# Linux — base tools
# =============================================================================
_eza() { install_tar_bin eza "https://github.com/eza-community/eza/releases/download/$1/eza_${UARCH}-unknown-linux-$([[ $UARCH == x86_64 ]] && echo musl || echo gnu).tar.gz" ./eza; }
_zellij() { install_tar_bin zellij "https://github.com/zellij-org/zellij/releases/download/$1/zellij-${UARCH}-unknown-linux-musl.tar.gz"; }
_lazygit() { install_tar_bin lazygit "https://github.com/jesseduffield/lazygit/releases/download/$1/lazygit_${1#v}_linux_$([[ $UARCH == x86_64 ]] && echo x86_64 || echo arm64).tar.gz"; }
_yq() { install_bin yq "https://github.com/mikefarah/yq/releases/download/$1/yq_linux_${ARCH}"; }
_zoxide() { curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; }
_ohmyposh() { curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin; }
_cliphist() { go install "go.senan.xyz/cliphist@$1"; }

install_linux() {
    section "Base packages"

    apt_refresh
    apt_install "${APT_CORE[@]}"
    apt_install "${APT_BASE[@]}"

    if ! $DRY_RUN; then
        mkdir -p ~/bin ~/.local/bin
        # Debian/Ubuntu ship fd and bat as fdfind / batcat; expose the usual names.
        cmd_exists fd || ln -sf "$(command -v fdfind)" ~/.local/bin/fd
        cmd_exists bat || ln -sf "$(command -v batcat)" ~/.local/bin/bat
    fi

    # Node.js LTS from NodeSource into /usr — apt's nodejs is too old (Copilot
    # CLI needs ≥ 22). Checks /usr/bin/node: other copies may shadow it on PATH.
    local node_major=0
    [[ -x /usr/bin/node ]] && node_major=$(/usr/bin/node -p 'process.versions.node.split(".")[0]')
    if skip_app node; then
        :
    elif ((node_major < 22)); then
        if step "node (NodeSource LTS)" "$( ((node_major)) && echo upgrade || echo install)" /usr/bin/node; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            apt_get install nodejs
            done_step
        fi
    elif $UPGRADE; then
        apt_install nodejs
    else
        ok node
    fi

    install_fzf

    gh_tool eza eza-community/eza _eza
    gh_tool zoxide ajeetdsouza/zoxide _zoxide

    # uv — Python package manager (macOS: brew); self-update is quick and idempotent
    if skip_app uv; then
        :
    elif ! cmd_exists uv; then
        if step uv; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
            done_step
        fi
    elif $UPGRADE; then
        if step uv; then
            uv self update
            done_step
        fi
    else
        ok uv
    fi

    gh_tool oh-my-posh JanDeDobbeleer/oh-my-posh _ohmyposh

    # pyenv (macOS: brew) — check directory, not command, since pyenv may not be in PATH yet
    if skip_app pyenv; then
        :
    elif [[ ! -d "$HOME/.pyenv" ]]; then
        if step pyenv install; then
            curl https://pyenv.run | bash
            done_step
        fi
    elif $UPGRADE; then
        if step pyenv upgrade "$HOME/.pyenv"; then
            "$HOME/.pyenv/bin/pyenv" update
            done_step
        fi
    else
        ok pyenv
    fi

    # wezterm — the fork, built from source
    install_wezterm_fork

    gh_tool zellij zellij-org/zellij _zellij
    gh_tool lazygit jesseduffield/lazygit _lazygit
    # yq — mikefarah's Go yq, same as brew (apt's yq is a different tool)
    gh_tool yq mikefarah/yq _yq

    install_go

    # cliphist — needs Go (macOS: uses Maccy instead)
    if omitted go && ! cmd_exists go && ! omitted cliphist; then
        warn cliphist "skipped — needs go, which is omitted"
    else
        gh_tool cliphist sentriz/cliphist _cliphist
    fi

    # Nerd Font — MesloLGS NF
    if skip_app font-meslo-lg-nerd-font; then
        :
    elif [[ ! -d "$HOME/.local/share/fonts/MesloLGS" ]]; then
        if step "MesloLGS NF font" install; then
            local font_dir="$HOME/.local/share/fonts/MesloLGS"
            mkdir -p "$font_dir"
            for variant in "Regular" "Bold" "Italic" "Bold%20Italic"; do
                curl -fsSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${variant}.ttf" \
                    -o "$font_dir/MesloLGS NF ${variant//%20/ }.ttf"
            done
            fc-cache -f "$font_dir"
            done_step
        fi
    else
        ok "MesloLGS NF font"
    fi
}

# =============================================================================
# DevOps tools — macOS
# =============================================================================
install_devops_macos() {
    section "DevOps tools"

    # Neovim nightly (brew HEAD build)
    if skip_app neovim; then
        :
    elif ! brew list --formula neovim &>/dev/null; then
        if step "neovim nightly" install nvim; then
            brew install --HEAD neovim
            done_step
        fi
    elif $UPGRADE; then
        if step "neovim nightly" upgrade nvim; then
            brew upgrade --fetch-HEAD neovim || true
            done_step
        fi
    else
        ok neovim
    fi

    # AWS CLI
    if skip_app aws; then
        :
    elif ! want aws; then
        ok aws
    elif is_latest aws "$(curl -fsSL https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"; then
        ok aws
        LATEST_VER=""
    elif step aws; then
        interactive sudo -v
        curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
        sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
        rm -f /tmp/AWSCLIV2.pkg
        done_step
    fi

    brew_install "${BREW_DEVOPS[@]}"

    install_claude
    npm_global copilot @github/copilot
}

# Claude CLI — native installer (npm install is deprecated); self-updating
install_claude() {
    if skip_app claude; then
        return
    elif ! cmd_exists claude; then
        if step claude; then
            curl -fsSL https://claude.ai/install.sh | bash
            done_step
        fi
    elif $UPGRADE; then
        if step claude; then
            claude update || true
            done_step
        fi
    else
        ok claude
    fi
}

# =============================================================================
# DevOps tools — Linux
# =============================================================================
_k9s() { install_tar_bin k9s "https://github.com/derailed/k9s/releases/download/$1/k9s_Linux_${ARCH}.tar.gz"; }
_eksctl() { install_tar_bin eksctl "https://github.com/eksctl-io/eksctl/releases/download/$1/eksctl_Linux_${ARCH}.tar.gz"; }
_argocd() { install_bin argocd "https://github.com/argoproj/argo-cd/releases/download/$1/argocd-linux-${ARCH}"; }
_tfsec() { install_bin tfsec "https://github.com/aquasecurity/tfsec/releases/download/$1/tfsec-linux-${ARCH}"; }
_terraform_docs() { install_tar_bin terraform-docs "https://github.com/terraform-docs/terraform-docs/releases/download/$1/terraform-docs-$1-linux-${ARCH}.tar.gz"; }
_helm() { curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash; }
_actionlint() {
    local tmp
    tmp=$(mktemp -d)
    (cd "$tmp" && bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash) "${1#v}")
    sudo install "$tmp/actionlint" /usr/local/bin/
    rm -rf "$tmp"
}

install_devops_linux() {
    section "DevOps tools"

    # Neovim nightly (macOS: brew --HEAD neovim). The nightly release notes
    # start with its `nvim --version` line, so an unchanged build is skipped.
    if skip_app neovim; then
        :
    elif ! want nvim; then
        ok neovim
    elif is_latest nvim "$(gh_api repos/neovim/neovim/releases/tags/nightly | jq -r .body | grep -m1 -oE 'NVIM v[^ ]+' | cut -c6- || true)"; then
        ok "neovim nightly"
        LATEST_VER=""
    elif step "neovim nightly" "" nvim; then
        local nvim_arch
        nvim_arch=$([[ $UARCH == x86_64 ]] && echo x86_64 || echo arm64)
        curl -fsSL "https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-${nvim_arch}.tar.gz" -o /tmp/nvim.tar.gz
        sudo rm -rf /opt/nvim-linux-*
        sudo tar -xzf /tmp/nvim.tar.gz -C /opt/
        sudo ln -sf "/opt/nvim-linux-${nvim_arch}/bin/nvim" /usr/local/bin/nvim
        rm /tmp/nvim.tar.gz
        done_step
    fi

    # AWS CLI — latest version is the top of its CHANGELOG
    if skip_app aws; then
        :
    elif ! want aws; then
        ok aws
    elif is_latest aws "$(curl -fsSL https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"; then
        ok aws
        LATEST_VER=""
    elif step aws; then
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${UARCH}.zip" -o "/tmp/awscliv2.zip"
        unzip -qo /tmp/awscliv2.zip -d /tmp
        sudo /tmp/aws/install --update
        rm -rf /tmp/aws /tmp/awscliv2.zip
        done_step
    fi

    # HashiCorp apt repo (terraform + vault)
    apt_repo hashicorp https://apt.releases.hashicorp.com/gpg \
        "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

    # GitHub CLI apt repo
    apt_repo github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"

    # Azure CLI — Microsoft's script adds their apt repo, then apt keeps it current
    if ! omitted azure-cli && ! cmd_exists az && step "azure-cli apt repo" install; then
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        done_step
    fi

    # apt-managed: terraform, vault, gh, az, ansible, yamllint, maven, .NET 8 SDK
    apt_install "${APT_DEVOPS[@]}"

    # kubectl — latest stable from dl.k8s.io
    if skip_app kubectl; then
        :
    elif ! want kubectl; then
        ok kubectl
    else
        local k8s_ver
        k8s_ver=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
        if is_latest kubectl "$k8s_ver"; then
            ok kubectl
            LATEST_VER=""
        elif step kubectl; then
            install_bin kubectl "https://dl.k8s.io/release/${k8s_ver}/bin/linux/${ARCH}/kubectl"
            done_step
        fi
    fi

    gh_tool helm helm/helm _helm
    gh_tool k9s derailed/k9s _k9s
    gh_tool eksctl eksctl-io/eksctl _eksctl
    gh_tool argocd argoproj/argo-cd _argocd
    gh_tool actionlint rhysd/actionlint _actionlint
    gh_tool tfsec aquasecurity/tfsec _tfsec
    gh_tool terraform-docs terraform-docs/terraform-docs _terraform_docs

    # deno → ~/.local/bin (already on PATH via my_aliases.sh); upgrade checks itself
    if skip_app deno; then
        :
    elif ! cmd_exists deno; then
        if step deno; then
            curl -fsSL https://deno.land/install.sh | DENO_INSTALL="$HOME/.local" sh -s -- -y --no-modify-path
            done_step
        fi
    elif $UPGRADE; then
        if step deno; then
            deno upgrade
            done_step
        fi
    else
        ok deno
    fi

    install_claude

    # Copilot CLI (needs Node ≥ 22 — installed in install_linux)
    npm_global copilot @github/copilot
    # tree-sitter CLI — required by nvim-treesitter (main branch) for parser compilation
    npm_global tree-sitter tree-sitter-cli

    # keyd — kernel-level key remapping (Wayland-compatible, macOS uses hidutil instead)
    # Not in apt; build from source
    if skip_app keyd; then
        :
    else
        if cmd_exists keyd; then
            ok keyd
        elif step keyd install; then
            apt_get install gcc make libevdev-dev libudev-dev
            rm -rf /tmp/keyd
            git clone https://github.com/rvaiya/keyd.git /tmp/keyd
            make -C /tmp/keyd
            sudo make -C /tmp/keyd install
            rm -rf /tmp/keyd
            done_step
        fi
        if [[ "$(readlink /etc/keyd/default.conf 2>/dev/null)" != "$DOTFILES/linux/keyd/default.conf" ]] &&
            step "keyd config" install; then
            sudo mkdir -p /etc/keyd
            sudo ln -sf "$DOTFILES/linux/keyd/default.conf" /etc/keyd/default.conf
            done_step
        fi
        if ! { systemctl is-enabled --quiet keyd 2>/dev/null && systemctl is-active --quiet keyd; } &&
            step "keyd service" install; then
            sudo systemctl enable --now keyd
            done_step
        fi
    fi
}

# =============================================================================
# Shell & editor — both OS
# =============================================================================
install_shell() {
    section "Shell & editor"

    # Set zsh as default shell (via sudo: no password prompt on Linux, where
    # sudo is already primed; macOS asks for it)
    local zsh_path
    zsh_path=$(command -v zsh || true)
    if [[ -z "$zsh_path" ]]; then
        warn "zsh" "not installed — run the base section"
    elif [[ "$(login_shell)" == "$zsh_path" ]]; then
        ok "zsh default shell"
    elif $DRY_RUN; then
        out "  ${C_YELLOW}+${C_RESET} zsh ${C_DIM}would become the default shell${C_RESET}"
    else
        grep -qx "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        interactive sudo chsh -s "$zsh_path" "$USER"
        SHELL_CHANGED=true
        out "  ${C_GREEN}✓${C_RESET} zsh ${C_DIM}set as default shell${C_RESET}"
    fi

    # Tmux Plugin Manager
    if skip_app tpm; then
        :
    elif [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
        if step tpm install; then
            git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
            done_step
        fi
    elif $UPGRADE; then
        if step tpm upgrade "$HOME/.tmux/plugins/tpm"; then
            git -C "$HOME/.tmux/plugins/tpm" pull --ff-only
            done_step
        fi
    else
        ok tpm
    fi

    # Neovim Python support
    if skip_app pynvim; then
        :
    elif ! python3 -c "import pynvim" &>/dev/null; then
        if step pynvim install py:pynvim; then
            pip3 install -U pynvim --break-system-packages 2>/dev/null || pip3 install -U pynvim || true
            done_step
        fi
    elif $UPGRADE; then
        if step pynvim upgrade py:pynvim; then
            pip3 install -U pynvim --break-system-packages 2>/dev/null || pip3 install -U pynvim || true
            done_step
        fi
    else
        ok pynvim
    fi

    # Zsh completions — fetched from upstream, not tracked in dotfiles
    local tf_comp_root="$HOME/.config/zsh-completion"
    local tf_comp="$tf_comp_root/terraform/_terraform"
    if [[ ! -s "$tf_comp" ]] || $UPGRADE; then
        if step "zsh completions" "$([[ -s "$tf_comp" ]] && echo update || echo install)" "$tf_comp"; then
            # Remove broken symlink that would block directory creation
            if [[ -L "$tf_comp_root" && ! -e "$tf_comp_root" ]]; then rm "$tf_comp_root"; fi
            mkdir -p "$(dirname "$tf_comp")"
            curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/terraform/_terraform -o "$tf_comp"
            done_step
        fi
    else
        ok "zsh completions"
    fi
}

# =============================================================================
# Symlinks + per-OS desktop config
# =============================================================================
create_links() {
    section "Symlinks"
    local src dst
    while IFS='|' read -r src dst; do
        symlink "$DOTFILES/$src" "$dst"
    done < <(links)
    if ((LINKS_OK)); then ok "$LINKS_OK links"; fi
    if $DRY_RUN; then return; fi

    if [[ "$OS" == "macos" ]]; then
        # Caps Lock → letter 'a' via hidutil (persisted through launchd)
        local plist_dst="$HOME/Library/LaunchAgents/com.user.capslock.plist"
        if ! launchctl print "gui/$(id -u)/com.user.capslock" &>/dev/null; then
            if launchctl bootstrap "gui/$(id -u)" "$plist_dst"; then
                out "  ${C_GREEN}✓${C_RESET} capslock ${C_DIM}remapped to 'a' (hidutil)${C_RESET}"
            else
                warn "capslock remap" "launchctl bootstrap failed (no GUI session?)"
            fi
        fi
        return
    fi

    [[ -x "$DOTFILES/linux/bin/clipboard-picker" ]] || chmod +x "$DOTFILES/linux/bin/clipboard-picker"

    # COSMIC shortcuts — apply sed substitution and compare md5 of the result
    # against the live file so template changes in git always propagate
    local cosmic_shortcuts="$HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom"
    local template="$DOTFILES/linux/cosmic/shortcuts/custom"
    mkdir -p "$(dirname "$cosmic_shortcuts")"
    # Remove any existing symlink so writes go to a real file, not back into the repo
    if [[ -L "$cosmic_shortcuts" ]]; then rm "$cosmic_shortcuts"; fi
    local expected_content expected_md5 live_md5
    expected_content=$(sed "s|/home/YOUR_USERNAME|$HOME|g" "$template")
    expected_md5=$(echo "$expected_content" | md5sum | awk '{print $1}')
    live_md5=$(md5sum "$cosmic_shortcuts" 2>/dev/null | awk '{print $1}') || true
    if [[ "$expected_md5" != "$live_md5" ]]; then
        echo "$expected_content" >"$cosmic_shortcuts"
        out "  ${C_GREEN}✓${C_RESET} COSMIC shortcuts ${C_DIM}updated${C_RESET}"
    else
        ok "COSMIC shortcuts"
    fi

    # Start cliphist daemon for the current session (autostart handles future logins)
    if cmd_exists wl-paste && [[ -x "$HOME/go/bin/cliphist" && -n "${WAYLAND_DISPLAY:-}" ]]; then
        if ! pgrep -f "wl-paste --watch" >/dev/null 2>&1; then
            nohup wl-paste --watch "$HOME/go/bin/cliphist" store &>/dev/null &
            out "  ${C_GREEN}✓${C_RESET} cliphist daemon ${C_DIM}started${C_RESET}"
        fi
    fi
}

# =============================================================================
# Doctor — read-only health check
# =============================================================================
DOCTOR_TOOLS="zsh git tmux rg fd bat jq yq fzf eza zoxide uv oh-my-posh pyenv zellij lazygit
go node npm nvim aws terraform vault terraform-docs gh az ansible kubectl helm k9s eksctl
argocd actionlint tfsec deno claude copilot tree-sitter wezterm"
DOCTOR_TOOLS_LINUX="cliphist keyd"

# A doctor tool belongs to an omitted app (command names differ from app names)
doctor_omitted() {
    local names=$1 a
    case "$1" in
    rg) names=ripgrep ;;
    az) names=azure-cli ;;
    nvim) names=neovim ;;
    kubectl) names="kubectl kubernetes-cli" ;;
    tree-sitter) names=tree-sitter-cli ;;
    fd) names="fd fd-find" ;;
    npm) names=node ;;
    esac
    for a in $names; do
        if skip_app "$a"; then return 0; fi
    done
    return 1
}

real_path() { realpath "$1" 2>/dev/null || printf '%s' "$1"; }

run_doctor() {
    # The PATH an interactive zsh really gets (zshrc adds dirs this script doesn't know).
    local user_path
    user_path=$(zsh -ic 'print -r -- "$PATH"' 2>/dev/null </dev/null | tail -n 1 || true)
    [[ -n "$user_path" ]] || user_path=$PATH

    section "Tools"
    local tools=$DOCTOR_TOOLS t dir f first seen copies
    [[ "$OS" == "macos" ]] || tools+=" $DOCTOR_TOOLS_LINUX"
    for t in $tools; do
        if doctor_omitted "$t"; then continue; fi
        first="" seen="" copies=()
        local IFS=:
        for dir in $user_path; do
            f="$dir/$t"
            [[ -x "$f" && ! -d "$f" ]] || continue
            local rp
            rp=$(real_path "$f")
            [[ " $seen " == *" $rp "* ]] && continue
            seen+=" $rp"
            if [[ -z "$first" ]]; then
                first=$f
            elif ! cmp -s "$(real_path "$first")" "$rp"; then
                copies+=("$f")
            fi
        done
        unset IFS
        if [[ -z "$first" ]]; then
            warn "$t" "missing — run ./init.sh"
        elif ((${#copies[@]})); then
            local v1 v2 c
            v1=$(ver_of "$first")
            for c in "${copies[@]}"; do
                v2=$(ver_of "$c")
                warn "$t" "$(pretty_path "$first")${v1:+ ($v1)} shadows $(pretty_path "$c")${v2:+ ($v2)}"
            done
        else
            ok "$t"
        fi
    done

    if [[ "$OS" != "macos" ]]; then
        section "Apt repos"
        local repo key_url keyring tmp
        while IFS='|' read -r repo key_url keyring; do
            if [[ ! -f "/etc/apt/sources.list.d/$repo.list" ]]; then
                warn "$repo" "repo not configured — run ./init.sh"
                continue
            fi
            tmp=$(mktemp)
            if ! curl -fsSL "$key_url" | gpg --batch --yes --dearmor -o "$tmp" 2>/dev/null; then
                warn "$repo" "could not download the signing key to compare"
            elif cmp -s "$tmp" "$keyring"; then
                ok "$repo"
            else
                fail "$repo" "signing key is stale — apt can't update it; run ./init.sh"
            fi
            rm -f "$tmp"
        done <<EOF
hashicorp|https://apt.releases.hashicorp.com/gpg|/usr/share/keyrings/hashicorp-archive-keyring.gpg
github-cli|https://cli.github.com/packages/githubcli-archive-keyring.gpg|/usr/share/keyrings/githubcli-archive-keyring.gpg
EOF
    fi

    section "Symlinks"
    local src dst n_links=0
    while IFS='|' read -r src dst; do
        if [[ -L "$dst" && "$(readlink "$dst")" == "$DOTFILES/$src" ]]; then
            if [[ -e "$dst" ]]; then
                n_links=$((n_links + 1))
            else
                fail "$(pretty_path "$dst")" "link target is missing in the repo"
            fi
        elif [[ -L "$dst" ]]; then
            warn "$(pretty_path "$dst")" "points to $(readlink "$dst") — run ./init.sh"
        elif [[ -e "$dst" ]]; then
            warn "$(pretty_path "$dst")" "is a regular file, not a link — run ./init.sh"
        else
            warn "$(pretty_path "$dst")" "missing — run ./init.sh"
        fi
    done < <(links)
    if ((n_links)); then ok "$n_links links"; fi

    section "Shell & repo"
    local zsh_path
    zsh_path=$(command -v zsh || true)
    if [[ -n "$zsh_path" && "$(login_shell)" == "$zsh_path" ]]; then
        ok "zsh default shell"
    else
        warn "default shell" "is $(login_shell), not zsh — run ./init.sh"
    fi
    local dirty
    dirty=$(git -C "$DOTFILES" status --porcelain 2>/dev/null || true)
    if [[ -z "$dirty" ]]; then
        ok "dotfiles repo clean"
    else
        warn "dotfiles repo has uncommitted changes" "(an installer may have edited a linked file)"
        sed 's/^/      /' <<<"$dirty" >&3
    fi
    flush_ok
}

# =============================================================================
# Run
# =============================================================================
if $DOCTOR; then
    run_doctor
    out ""
    if ((N_ERR)); then
        corner=$C_RED title="${C_BOLD}${C_RED}Problems found${C_RESET}"
    elif ((N_WARN)); then
        corner=$C_YELLOW title="${C_BOLD}${C_YELLOW}Mostly healthy${C_RESET}"
    else
        corner=$C_GREEN title="${C_BOLD}${C_GREEN}All healthy${C_RESET}"
    fi
    out "  ${corner}╭─${C_RESET} $title"
    panel_row "${corner}│ ${C_RESET}" "Checked" "$OS_NAME ${C_DIM}· $UARCH${C_RESET}"
    panel_row "${corner}│ ${C_RESET}" "Result" "$N_OK ok ${C_DIM}·${C_RESET} $N_WARN warnings ${C_DIM}·${C_RESET} $N_ERR errors"
    panel_row "${corner}╰─${C_RESET}" "Fix" "${C_CYAN}./init.sh${C_RESET} ${C_DIM}fixes links, repos, missing tools · remove shadowing copies by hand${C_RESET}"
    out ""
    exit $((N_ERR ? 1 : 0))
fi

# sudo up front on Linux (prompt now, not hidden behind a spinner), kept alive
# for the whole run.
if [[ "$OS" != "macos" && $EUID -ne 0 ]] && ! $DRY_RUN; then
    if ! sudo -n true 2>/dev/null; then
        out ""
        out "  ${C_DIM}sudo is needed for system packages${C_RESET}"
        interactive sudo -v
    fi
    (while kill -0 $$ 2>/dev/null; do
        sudo -n true 2>/dev/null || true
        sleep 50
    done) &
    SUDO_PID=$!
fi

# Clone dotfiles
if [[ ! -d "$DOTFILES" ]] && step "dotfiles repo" install; then
    if [[ "$OS" != "macos" ]] && ! cmd_exists git; then
        apt_get update
        apt_get install git
    fi
    mkdir -p "$(dirname "$DOTFILES")"
    git clone https://github.com/jad617/dotfiles.git "$DOTFILES"
    done_step
fi

if want_section base; then
    if [[ "$OS" == "macos" ]]; then install_macos; else install_linux; fi
fi
if want_section devops; then
    if [[ "$OS" == "macos" ]]; then install_devops_macos; else install_devops_linux; fi
fi
if want_section shell; then install_shell; fi
if want_section links; then create_links; fi
flush_ok

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
G="${C_GREEN}│ ${C_RESET}"
out ""
if $DRY_RUN; then
    out "  ${C_YELLOW}╭─${C_RESET} ${C_BOLD}${C_YELLOW}Dry run complete${C_RESET} ${C_DIM}— nothing was changed${C_RESET}"
    G="${C_YELLOW}│ ${C_RESET}"
    panel_row "$G" "Ran on" "$OS_NAME ${C_DIM}· $UARCH ·${C_RESET} ${C_BOLD}$MODE${C_RESET} mode"
    panel_row "$G" "Would" "install $N_INSTALLED ${C_DIM}·${C_RESET} upgrade $N_UPGRADED ${C_DIM}·${C_RESET} check $N_MAYBE ${C_DIM}·${C_RESET} $N_OK up to date"
    if ((${#INSTALLED_LIST[@]})); then panel_row "$G" "Install" "$(join ", " "${INSTALLED_LIST[@]}")"; fi
    if ((${#UPGRADED_LIST[@]})); then panel_row "$G" "Upgrade" "$(join ", " "${UPGRADED_LIST[@]}")"; fi
    if ((${#MAYBE_LIST[@]})); then
        panel_row "$G" "Check" "$(join ", " "${MAYBE_LIST[@]}") ${C_DIM}(self-updaters: newer version unknown until run)${C_RESET}"
    fi
    omit_rows "$G"
    panel_row "$G" "Apply" "${C_CYAN}./init.sh$($UPGRADE && echo " --upgrade")${OMIT_ADD:+ --omit-app ${OMIT_ADD#,}}${OMIT_DEL:+ --add-app ${OMIT_DEL#,}}${C_RESET} ${C_DIM}(same options, without --dry-run)${C_RESET}"
    panel_row "${C_YELLOW}╰─${C_RESET}" "Log" "${C_DIM}$(pretty_path "$LOG")${C_RESET}"
    out ""
    exit 0
fi

out "  ${C_GREEN}╭─${C_RESET} ${C_BOLD}${C_GREEN}Done${C_RESET} ${C_DIM}in $(fmt_time "$SECONDS")${C_RESET}"
panel_row "$G" "Ran on" "$OS_NAME ${C_DIM}· $UARCH ·${C_RESET} ${C_BOLD}$MODE${C_RESET} mode"
panel_row "$G" "Result" "$N_INSTALLED installed ${C_DIM}·${C_RESET} $N_UPGRADED upgraded ${C_DIM}·${C_RESET} $N_OK up to date"
if ((${#INSTALLED_LIST[@]})); then panel_row "$G" "Installed" "$(join ", " "${INSTALLED_LIST[@]}")"; fi
if ((${#UPGRADED_LIST[@]})); then panel_row "$G" "Upgraded" "$(join ", " "${UPGRADED_LIST[@]}")"; fi
if ((${#STEP_TIMES[@]})); then
    slowest=$(printf '%s\n' "${STEP_TIMES[@]}" | sort -rn | head -3 | awk '{s=$1; $1=""; printf "%s%s %ss", (NR>1?" · ":""), substr($0,2), s}')
    panel_row "$G" "Slowest" "${C_DIM}$slowest${C_RESET}"
fi
omit_rows "$G"
if $SHELL_CHANGED; then
    panel_row "$G" "Shell" "${C_YELLOW}zsh is now your default — log out and back in${C_RESET}"
fi
if $UPGRADE; then
    panel_row "$G" "Next" "${C_DIM}plain${C_RESET} ./init.sh ${C_DIM}only installs what's missing, without upgrading${C_RESET}"
else
    panel_row "$G" "Upgrade" "${C_CYAN}./init.sh --upgrade${C_RESET} ${C_DIM}to bring everything to the latest version${C_RESET}"
fi
panel_row "$G" "Preview" "${C_CYAN}./init.sh --upgrade --dry-run${C_RESET} ${C_DIM}to see what an upgrade would change${C_RESET}"
panel_row "$G" "Check" "${C_CYAN}./init.sh --doctor${C_RESET} ${C_DIM}to check PATH shadowing, apt keys and links${C_RESET}"
if $VERBOSE; then
    out "  ${C_GREEN}╰─${C_RESET}"
else
    panel_row "${C_GREEN}╰─${C_RESET}" "Log" "${C_DIM}$(pretty_path "$LOG")${C_RESET}"
fi
out ""
notify "Done in $(fmt_time "$SECONDS") · $N_INSTALLED installed · $N_UPGRADED upgraded"
