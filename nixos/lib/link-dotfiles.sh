#!/usr/bin/env bash
# =============================================================================
# Links this checkout's configs into a NixOS user's home (zsh, nvim, wezterm,
# tmux, Hyprland, GTK, wallpapers) and seeds Caelestia's shell.json.
# Shared by init.sh (on NixOS, as you) and install-from-linux.sh (at install
# time, as root, into the new system), so the first login already has the
# Hyprland config that starts Caelestia, with or without network.
#
#   link-dotfiles.sh                                   your own home, this checkout
#   link-dotfiles.sh --root /mnt --user NAME --owner UID:GID
#       the home of NAME inside /mnt; links point to /home/NAME/nodestack/dotfiles,
#       which must already be in /mnt (the installer copies it there first)
#
# Something real in the way (a file or folder, e.g. the hyprland.lua that
# Hyprland writes when it finds no config) is moved to <name>.bak-<date>, never deleted.
# =============================================================================
set -euo pipefail

ROOT="" USERNAME=$(id -un) OWNER=""
while (($#)); do
    case $1 in
    --root) ROOT=${2%/} && shift 2 ;;
    --user) USERNAME=$2 && shift 2 ;;
    --owner) OWNER=$2 && shift 2 ;;
    *) echo "usage: $0 [--root DIR --user NAME --owner UID:GID]" >&2 && exit 2 ;;
    esac
done

HOME_DIR=/home/$USERNAME
if [[ -z $ROOT ]]; then
    HOME_DIR=$HOME
    DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" # this file is in nixos/lib
else
    DOTFILES=$HOME_DIR/nodestack/dotfiles
fi
NIXOS_DIR=$DOTFILES/nixos
STAMP=$(date +%Y%m%d-%H%M%S)
[[ -d $ROOT$NIXOS_DIR ]] || { echo "error: no checkout at $ROOT$NIXOS_DIR" >&2 && exit 1; }

own() { [[ -z $OWNER ]] || chown -h "$OWNER" "$@"; }
mkdirs() { # DIR (as seen on NixOS): create it and the missing parents under the home, owned by the user
    local d=$1 todo=()
    while [[ $d == "$HOME_DIR"/* && ! -d $ROOT$d && ! -L $ROOT$d ]]; do todo=("$d" ${todo[@]+"${todo[@]}"}) && d=$(dirname "$d"); done
    for d in ${todo[@]+"${todo[@]}"}; do mkdir "$ROOT$d" && own "$ROOT$d"; done
    return 0
}
link() { # SRC DST, both as seen on NixOS
    local src=$1 dst=$2
    [[ -e $ROOT$src ]] || { echo "  skipped (missing in the checkout): $src" && return 0; }
    mkdirs "$(dirname "$dst")"
    # e.g. ~/Pictures linked to /backup/shared/Pictures while /backup is not mounted
    [[ -d $ROOT$(dirname "$dst") ]] || { echo "  skipped (not available now): $(dirname "$dst")" && return 0; }
    # Already right: leave it (no moment without it, e.g. for Hyprland's config watcher)
    [[ -L $ROOT$dst && $(readlink "$ROOT$dst") == "$src" ]] && return 0
    if [[ -L $ROOT$dst ]]; then
        rm "$ROOT$dst"
    elif [[ -e $ROOT$dst ]]; then
        mv "$ROOT$dst" "$ROOT$dst.bak-$STAMP"
        echo "  moved aside: $dst -> $(basename "$dst").bak-$STAMP"
    fi
    ln -s "$src" "$ROOT$dst"
    own "$ROOT$dst"
    echo "  linked: ${dst/#$HOME_DIR/\~}"
}

# Shell
link "$DOTFILES/shell/zsh/my_aliases.sh" "$HOME_DIR/.my_aliases.sh"
link "$DOTFILES/shell/zsh/zshrc" "$HOME_DIR/.zshrc"
link "$DOTFILES/shell/zsh/completions/_claude" "$HOME_DIR/.zfunc/_claude"
# Commands (~/.local/bin is on PATH via my_aliases.sh)
link "$NIXOS_DIR/bin/nixos-shortcuts" "$HOME_DIR/.local/bin/nixos-shortcuts"
link "$NIXOS_DIR/bin/nixos-update" "$HOME_DIR/.local/bin/nixos-update"
link "$NIXOS_DIR/bin/nixos-sync" "$HOME_DIR/.local/bin/nixos-sync"
link "$DOTFILES/shell/prompt/ohmyposh" "$HOME_DIR/.config/ohmyposh"
# Editor
link "$DOTFILES/editors/nvim" "$HOME_DIR/.config/nvim"
# Terminal
link "$DOTFILES/terminal/wezterm/wezterm.lua" "$HOME_DIR/.wezterm.lua"
link "$DOTFILES/terminal/zellij" "$HOME_DIR/.config/zellij"
link "$DOTFILES/terminal/tmux/tmux.conf" "$HOME_DIR/.tmux.conf"
# Hyprland (its hyprland.lua starts Caelestia)
link "$NIXOS_DIR/config/hypr" "$HOME_DIR/.config/hypr"
# GTK theme + icons
link "$NIXOS_DIR/config/gtk/settings.ini" "$HOME_DIR/.config/gtk-3.0/settings.ini"
link "$NIXOS_DIR/config/gtk/settings.ini" "$HOME_DIR/.config/gtk-4.0/settings.ini"
link "$NIXOS_DIR/config/gtk/gtk-4.0.css" "$HOME_DIR/.config/gtk-4.0/gtk.css"
# Wallpapers, screenshots
link "$DOTFILES/wallpapers" "$HOME_DIR/Pictures/Wallpapers"
[[ -L $ROOT$HOME_DIR/Pictures && ! -d $ROOT$HOME_DIR/Pictures ]] || mkdirs "$HOME_DIR/Pictures/screenshots"

# Caelestia CLI: the scheme leaves terminal colours alone (WezTerm keeps its own)
link "$NIXOS_DIR/config/caelestia/cli.json" "$HOME_DIR/.config/caelestia/cli.json"
# Caelestia shell defaults (opaque panels). Copied, not linked: Caelestia
# rewrites this file when settings change in its UI, so only seed it once
if [[ ! -e $ROOT$HOME_DIR/.config/caelestia/shell.json ]]; then
    mkdirs "$HOME_DIR/.config/caelestia"
    cp "$ROOT$NIXOS_DIR/config/caelestia/shell.json" "$ROOT$HOME_DIR/.config/caelestia/shell.json"
    own "$ROOT$HOME_DIR/.config/caelestia/shell.json"
    echo "  created: ~/.config/caelestia/shell.json"
fi
