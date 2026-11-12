#!/usr/bin/env bash
# =============================================================================
# One-time setup of a NixOS user's home that the system config can't do: things
# downloaded into the home, and opt-out flags. Used by install-from-linux.sh (at
# install time, as root, into the new system) and by init.sh (on NixOS, as you).
# Each item is skipped when it is already there; a failed download only warns
# (init.sh tries again).
#
#   home-setup.sh                                    your own home
#   home-setup.sh --root /mnt --user NAME --owner UID:GID
#       the home of NAME inside /mnt
#
# Items:
#   ~/.disable_copilot                       Copilot off in Neovim (remove it to turn it on)
#   ~/.tmux/plugins/tpm                      tmux plugin manager (prefix + I installs the plugins)
#   ~/.config/zsh-completion/terraform       Terraform completion for zsh
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
HOME_DIR=$ROOT/home/$USERNAME
[[ -n $ROOT ]] || HOME_DIR=$HOME
[[ -d $HOME_DIR ]] || { echo "error: no home at $HOME_DIR" >&2 && exit 1; }

own() { [[ -z $OWNER ]] || chown -R "$OWNER" "$@"; }
mkdir_own() { # DIR under the home: created with its missing parents, owned by the user
    local d=$1 top=$1
    while [[ ! -d $(dirname "$top") ]]; do top=$(dirname "$top"); done
    [[ -d $top ]] && return 0
    mkdir -p "$d" && own "$top"
}

# Copilot off in Neovim by default
if [[ ! -e $HOME_DIR/.disable_copilot ]]; then
    touch "$HOME_DIR/.disable_copilot" && own "$HOME_DIR/.disable_copilot"
    echo "  created: ~/.disable_copilot (Copilot off in Neovim; remove it to turn it on)"
fi

# tmux plugin manager
if [[ ! -d $HOME_DIR/.tmux/plugins/tpm ]]; then
    if command -v git >/dev/null; then
        mkdir_own "$HOME_DIR/.tmux/plugins"
        if git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$HOME_DIR/.tmux/plugins/tpm"; then
            own "$HOME_DIR/.tmux/plugins/tpm"
            echo "  installed: ~/.tmux/plugins/tpm (prefix + I in tmux installs the plugins)"
        else
            echo "  skipped: tmux plugin manager (download failed; init.sh tries again)"
        fi
    else
        echo "  skipped: tmux plugin manager (no git here; init.sh installs it)"
    fi
fi

# Terraform completion for zsh
TF_COMP=$HOME_DIR/.config/zsh-completion/terraform/_terraform
if [[ ! -s $TF_COMP ]]; then
    mkdir_own "$(dirname "$TF_COMP")"
    if curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/terraform/_terraform -o "$TF_COMP"; then
        own "$TF_COMP"
        echo "  installed: ~/.config/zsh-completion/terraform (zsh completion)"
    else
        rm -f "$TF_COMP"
        echo "  skipped: Terraform completion (download failed; init.sh tries again)"
    fi
fi
