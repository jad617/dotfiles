#!/usr/bin/env bash
# =============================================================================
# Idempotent dotfiles bootstrap — macOS & Pop!_OS
# =============================================================================
set -euo pipefail

DOTFILES="$HOME/nodestack/dotfiles"

# -----------------------------------------------------------------------------
# Detect OS
# -----------------------------------------------------------------------------
OS=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" == "pop" ]]; then
        OS="popos"
    else
        OS="linux"
    fi
fi

[[ -z "$OS" ]] && { echo "Unsupported OS: $OSTYPE"; exit 1; }
echo "==> Detected OS: $OS"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
symlink() {
    local src=$1 dst=$2
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
    echo "  linked: $dst"
}

clone_if_missing() {
    local repo=$1 dest=$2
    if [[ ! -d "$dest" ]]; then
        git clone "$repo" "$dest"
    else
        echo "  already exists: $dest"
    fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

# -----------------------------------------------------------------------------
# Clone dotfiles
# -----------------------------------------------------------------------------
mkdir -p ~/nodestack
clone_if_missing "https://github.com/jad617/dotfiles.git" "$DOTFILES"

# =============================================================================
# macOS
# =============================================================================
install_macos() {
    echo "==> Installing macOS packages"

    # Homebrew
    if ! cmd_exists brew; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Core
    brew install \
        zsh-syntax-highlighting \
        htop \
        wget \
        luajit \
        pwgen \
        bat \
        fd \
        ripgrep \
        tmux \
        watch \
        pyenv \
        pyenv-virtualenv \
        neovim \
        go \
        oh-my-posh \
        television \
        zellij \
        wezterm

    # DevOps
    if ! cmd_exists aws; then
        curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
        sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
        rm -f /tmp/AWSCLIV2.pkg
    fi

    brew tap hashicorp/tap
    brew install \
        hashicorp/tap/terraform \
        terraform-docs \
        ansible \
        kubectl \
        derailed/k9s/k9s \
        mysql-client@8.0 \
        helm

    # UI
    brew install --cask rectangle
    brew install maccy   # macOS clipboard manager (Linux: cliphist+wofi)

    # Kitty
    if ! cmd_exists kitty; then
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
    fi

    # Oh-My-Zsh + Powerlevel10k (macOS zshrc uses these)
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    clone_if_missing "https://github.com/romkatv/powerlevel10k.git" "$HOME/powerlevel10k"
}

# =============================================================================
# Pop!_OS / Linux
# =============================================================================
install_linux() {
    echo "==> Installing Linux packages"

    sudo apt update
    sudo apt install -y \
        zsh \
        zsh-syntax-highlighting \
        htop \
        wget \
        bat \
        fd-find \
        ripgrep \
        tmux \
        watch \
        neovim \
        golang \
        wl-clipboard \
        wofi \
        wtype \
        curl \
        git \
        unzip \
        jq

    mkdir -p ~/bin

    # oh-my-posh
    if ! cmd_exists oh-my-posh; then
        curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin
    fi

    # pyenv (macOS: brew, Linux: installer)
    if ! cmd_exists pyenv; then
        curl https://pyenv.run | bash
    fi

    # wezterm
    if ! cmd_exists wezterm; then
        curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
        echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
        sudo apt update && sudo apt install -y wezterm
    fi

    # zellij (macOS: brew, Linux: GitHub release)
    if ! cmd_exists zellij; then
        ZELLIJ_VER=$(curl -s https://api.github.com/repos/zellij-org/zellij/releases/latest | jq -r '.tag_name')
        curl -L "https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VER}/zellij-x86_64-unknown-linux-musl.tar.gz" -o /tmp/zellij.tar.gz
        tar -xzf /tmp/zellij.tar.gz -C /tmp
        sudo mv /tmp/zellij /usr/local/bin/
        rm /tmp/zellij.tar.gz
    fi

    # television (macOS: brew, Linux: GitHub release)
    if ! cmd_exists tv; then
        TV_VER=$(curl -s https://api.github.com/repos/alexpasmantier/television/releases/latest | jq -r '.tag_name')
        curl -L "https://github.com/alexpasmantier/television/releases/download/${TV_VER}/television-${TV_VER}-x86_64-unknown-linux-musl.tar.gz" -o /tmp/tv.tar.gz
        mkdir -p /tmp/tv && tar -xzf /tmp/tv.tar.gz -C /tmp/tv
        sudo mv /tmp/tv/tv /usr/local/bin/
        rm -rf /tmp/tv /tmp/tv.tar.gz
    fi

    # cliphist (macOS: uses Maccy instead)
    if ! cmd_exists cliphist; then
        go install go.senan.xyz/cliphist@latest
    fi

    # DevOps
    if ! cmd_exists aws; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
        unzip -q /tmp/awscliv2.zip -d /tmp
        sudo /tmp/aws/install
        rm -rf /tmp/aws /tmp/awscliv2.zip
    fi

    if ! cmd_exists terraform; then
        wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
            | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y terraform
    fi

    if ! cmd_exists kubectl; then
        curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi

    if ! cmd_exists helm; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    if ! cmd_exists k9s; then
        K9S_VER=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
        curl -L "https://github.com/derailed/k9s/releases/download/${K9S_VER}/k9s_linux_amd64.tar.gz" -o /tmp/k9s.tar.gz
        tar -xzf /tmp/k9s.tar.gz -C /tmp
        sudo mv /tmp/k9s /usr/local/bin/
        rm /tmp/k9s.tar.gz
    fi

    if ! cmd_exists ansible; then
        sudo apt install -y ansible
    fi

    # mysql-client (macOS: mysql-client@8.0 via brew)
    # sudo apt install -y mysql-client
}

# =============================================================================
# Common — after OS packages
# =============================================================================
install_common() {
    # Tmux Plugin Manager
    clone_if_missing "https://github.com/tmux-plugins/tpm" "$HOME/.tmux/plugins/tpm"

    # Neovim Python support
    pip3 install neovim --break-system-packages 2>/dev/null || pip3 install neovim || true
}

# =============================================================================
# Symlinks — common to both OS
# =============================================================================
create_common_symlinks() {
    echo "==> Creating common symlinks"
    symlink "$DOTFILES/shell/zsh/my_aliases.sh"          "$HOME/.my_aliases.sh"
    symlink "$DOTFILES/terminal/wezterm/wezterm.lua"     "$HOME/.wezterm.lua"
    symlink "$DOTFILES/editors/nvim"                     "$HOME/.config/nvim"
    symlink "$DOTFILES/shell/prompt/ohmyposh"            "$HOME/.config/ohmyposh"
    symlink "$DOTFILES/terminal/zellij"                  "$HOME/.config/zellij"
    symlink "$DOTFILES/terminal/kitty"                   "$HOME/.config/kitty"
    symlink "$DOTFILES/shell/zsh/television.config.toml" "$HOME/.config/television/config.toml"
}

# =============================================================================
# Symlinks — macOS only
# =============================================================================
create_macos_symlinks() {
    echo "==> Creating macOS symlinks"
    symlink "$DOTFILES/shell/zsh/zshrc"               "$HOME/.zshrc"
    symlink "$DOTFILES/shell/zsh/p10k.zsh"            "$HOME/.p10k.zsh"
    symlink "$DOTFILES/terminal/tmux/macos_tmux.conf" "$HOME/.tmux.conf"
}

# =============================================================================
# Symlinks — Linux (Pop!_OS) only
# =============================================================================
create_linux_symlinks() {
    echo "==> Creating Linux symlinks"
    symlink "$DOTFILES/shell/zsh/zshrc"                                                "$HOME/.zshrc"
    symlink "$DOTFILES/terminal/tmux/tmux.conf"                                        "$HOME/.tmux.conf"
    symlink "$DOTFILES/linux/wofi/config"                                              "$HOME/.config/wofi/config"
    symlink "$DOTFILES/linux/wofi/style.css"                                           "$HOME/.config/wofi/style.css"
    symlink "$DOTFILES/linux/autostart/cliphist-daemon.desktop"                        "$HOME/.config/autostart/cliphist-daemon.desktop"
    symlink "$DOTFILES/linux/bin/clipboard-picker"                                     "$HOME/bin/clipboard-picker"
    symlink "$DOTFILES/linux/cosmic/shortcuts/custom"                                  "$HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom"
}

# =============================================================================
# Run
# =============================================================================
case "$OS" in
    macos)
        install_macos
        install_common
        create_common_symlinks
        create_macos_symlinks
        ;;
    popos|linux)
        install_linux
        install_common
        create_common_symlinks
        create_linux_symlinks
        ;;
esac

echo ""
echo "==> Done! Restart your shell to apply changes."
