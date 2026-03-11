#!/usr/bin/env bash
# =============================================================================
# Idempotent dotfiles bootstrap — macOS & Pop!_OS
#
# Usage on a fresh machine:
#   bash <(curl -fsSL https://raw.githubusercontent.com/jad617/dotfiles/main/init.sh)
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
# Go — official installer (same on both OS)
# -----------------------------------------------------------------------------
install_go() {
    local arch
    if [[ "$(uname -m)" == "arm64" ]]; then arch="arm64"; else arch="amd64"; fi
    local goos
    if [[ "$OS" == "macos" ]]; then goos="darwin"; else goos="linux"; fi

    local latest
    latest=$(curl -s "https://go.dev/dl/?mode=json" | jq -r '.[0].version')

    if cmd_exists go && [[ "$(go version | awk '{print $3}')" == "$latest" ]]; then
        echo "  go $latest already installed"
        return
    fi

    echo "==> Installing Go $latest"
    local archive="${latest}.${goos}-${arch}.tar.gz"
    curl -fsSL "https://go.dev/dl/${archive}" -o "/tmp/${archive}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${archive}"
    rm "/tmp/${archive}"
    export PATH="/usr/local/go/bin:$PATH"
    echo "  go $(go version)"
}

# -----------------------------------------------------------------------------
# Clone dotfiles
# -----------------------------------------------------------------------------
mkdir -p ~/nodestack
clone_if_missing "https://github.com/jad617/dotfiles.git" "$DOTFILES"

# =============================================================================
# macOS — base tools
# =============================================================================
install_macos() {
    echo "==> Installing macOS base packages"

    if ! cmd_exists brew; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

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
        eza \
        zoxide \
        oh-my-posh \
        television \
        zellij \
        wezterm

    # Kitty
    if ! cmd_exists kitty; then
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
    fi

    # Oh-My-Zsh + Powerlevel10k
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    clone_if_missing "https://github.com/romkatv/powerlevel10k.git" "$HOME/powerlevel10k"

    install_go

    # Nerd Font
    brew install --cask font-meslo-lg-nerd-font

    # macOS clipboard manager
    brew install --cask rectangle
    brew install maccy

}

# =============================================================================
# Linux — base tools
# =============================================================================
install_linux() {
    echo "==> Installing Linux base packages"

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
        wl-clipboard \
        wofi \
        wtype \
        curl \
        git \
        unzip \
        jq \
        fontconfig \
        nodejs \
        npm

    mkdir -p ~/bin

    # eza (macOS: brew)
    if ! cmd_exists eza; then
        EZA_VER=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | jq -r '.tag_name')
        curl -L "https://github.com/eza-community/eza/releases/download/${EZA_VER}/eza_x86_64-unknown-linux-musl.tar.gz" -o /tmp/eza.tar.gz
        tar -xzf /tmp/eza.tar.gz -C /tmp
        sudo mv /tmp/eza /usr/local/bin/
        rm /tmp/eza.tar.gz
    fi

    # zoxide (macOS: brew)
    if ! cmd_exists zoxide; then
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi

    # oh-my-posh
    if ! cmd_exists oh-my-posh; then
        curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin
    fi

    # pyenv (macOS: brew)
    if ! cmd_exists pyenv; then
        curl https://pyenv.run | bash
    fi

    # wezterm
    if ! cmd_exists wezterm; then
        curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
        echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
        sudo apt update && sudo apt install -y wezterm
    fi

    # zellij (macOS: brew)
    if ! cmd_exists zellij; then
        ZELLIJ_VER=$(curl -s https://api.github.com/repos/zellij-org/zellij/releases/latest | jq -r '.tag_name')
        curl -L "https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VER}/zellij-x86_64-unknown-linux-musl.tar.gz" -o /tmp/zellij.tar.gz
        tar -xzf /tmp/zellij.tar.gz -C /tmp
        sudo mv /tmp/zellij /usr/local/bin/
        rm /tmp/zellij.tar.gz
    fi

    # television (macOS: brew)
    if ! cmd_exists tv; then
        TV_VER=$(curl -s https://api.github.com/repos/alexpasmantier/television/releases/latest | jq -r '.tag_name')
        curl -L "https://github.com/alexpasmantier/television/releases/download/${TV_VER}/television-${TV_VER}-x86_64-unknown-linux-musl.tar.gz" -o /tmp/tv.tar.gz
        mkdir -p /tmp/tv && tar -xzf /tmp/tv.tar.gz -C /tmp/tv
        sudo mv /tmp/tv/tv /usr/local/bin/
        rm -rf /tmp/tv /tmp/tv.tar.gz
    fi

    install_go

    # cliphist — needs Go in PATH first (macOS: uses Maccy instead)
    if ! cmd_exists cliphist; then
        go install go.senan.xyz/cliphist@latest
    fi

    # Nerd Font — MesloLGS NF
    if ! fc-list | grep -qi "MesloLGS"; then
        echo "==> Installing MesloLGS NF font"
        FONT_DIR="$HOME/.local/share/fonts/MesloLGS"
        mkdir -p "$FONT_DIR"
        for variant in "Regular" "Bold" "Italic" "Bold%20Italic"; do
            curl -fsSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${variant}.ttf" \
                -o "$FONT_DIR/MesloLGS NF ${variant//%20/ }.ttf"
        done
        fc-cache -fv "$FONT_DIR"
    fi
}

# =============================================================================
# DevOps tools — macOS
# =============================================================================
install_devops_macos() {
    echo "==> Installing macOS DevOps tools"

    # Neovim nightly (macOS: brew HEAD)
    brew install --HEAD neovim

    # AWS CLI
    if ! cmd_exists aws; then
        curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
        sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
        rm -f /tmp/AWSCLIV2.pkg
    fi

    brew tap hashicorp/tap
    brew install \
        hashicorp/tap/terraform \
        hashicorp/tap/vault \
        terraform-docs \
        ansible \
        kubectl \
        derailed/k9s/k9s \
        mysql-client@8.0 \
        helm

    # Claude CLI
    if ! cmd_exists claude; then
        npm install -g @anthropic-ai/claude-code
    fi
}

# =============================================================================
# DevOps tools — Linux
# =============================================================================
install_devops_linux() {
    echo "==> Installing Linux DevOps tools"

    # Neovim nightly (macOS: brew --HEAD neovim)
    echo "==> Installing Neovim nightly"
    curl -LO --output-dir /tmp https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz
    sudo tar -xzf /tmp/nvim-linux-x86_64.tar.gz -C /opt/
    sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm /tmp/nvim-linux-x86_64.tar.gz

    # AWS CLI
    if ! cmd_exists aws; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
        unzip -q /tmp/awscliv2.zip -d /tmp
        sudo /tmp/aws/install
        rm -rf /tmp/aws /tmp/awscliv2.zip
    fi

    # HashiCorp apt repo (terraform + vault)
    if ! cmd_exists terraform || ! cmd_exists vault; then
        wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
            | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update
        sudo apt install -y terraform vault
    fi

    # kubectl
    if ! cmd_exists kubectl; then
        curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi

    # helm
    if ! cmd_exists helm; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # k9s (macOS: brew)
    if ! cmd_exists k9s; then
        K9S_VER=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
        curl -L "https://github.com/derailed/k9s/releases/download/${K9S_VER}/k9s_linux_amd64.tar.gz" -o /tmp/k9s.tar.gz
        tar -xzf /tmp/k9s.tar.gz -C /tmp
        sudo mv /tmp/k9s /usr/local/bin/
        rm /tmp/k9s.tar.gz
    fi

    # ansible
    if ! cmd_exists ansible; then
        sudo apt install -y ansible
    fi

    # Claude CLI
    if ! cmd_exists claude; then
        npm install -g @anthropic-ai/claude-code
    fi

    # mysql-client (macOS: mysql-client@8.0 via brew)
    # sudo apt install -y mysql-client

    # keyd — kernel-level key remapping (Wayland-compatible, macOS uses hidutil instead)
    if ! cmd_exists keyd; then
        sudo apt install -y keyd
    fi
    sudo mkdir -p /etc/keyd
    sudo cp "$DOTFILES/linux/keyd/default.conf" /etc/keyd/default.conf
    sudo systemctl enable --now keyd
}

# =============================================================================
# Common — after OS + DevOps packages
# =============================================================================
install_common() {
    # Set zsh as default shell
    if [[ "$SHELL" != "$(which zsh)" ]]; then
        echo "==> Setting zsh as default shell"
        chsh -s "$(which zsh)"
    fi

    # Tmux Plugin Manager
    clone_if_missing "https://github.com/tmux-plugins/tpm" "$HOME/.tmux/plugins/tpm"

    # Neovim Python support
    pip3 install neovim --break-system-packages 2>/dev/null || pip3 install neovim || true

    # Zsh completions — fetched from upstream, not tracked in dotfiles
    echo "==> Fetching zsh completions"
    local tf_comp="$HOME/.config/zsh-completion/terraform/_terraform"
    mkdir -p "$(dirname "$tf_comp")"
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/terraform/_terraform -o "$tf_comp"
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

    # Caps Lock → letter 'a' via hidutil (persisted through launchd)
    local plist_src="$DOTFILES/mac/capslock.plist"
    local plist_dst="$HOME/Library/LaunchAgents/com.user.capslock.plist"
    symlink "$plist_src" "$plist_dst"
    launchctl unload "$plist_dst" 2>/dev/null || true
    launchctl load "$plist_dst"
    echo "  capslock remapped to 'a' (hidutil)"
}

# =============================================================================
# Symlinks — Linux (Pop!_OS) only
# =============================================================================
create_linux_symlinks() {
    echo "==> Creating Linux symlinks"
    symlink "$DOTFILES/shell/zsh/zshrc"                                                          "$HOME/.zshrc"
    symlink "$DOTFILES/terminal/tmux/tmux.conf"                                                  "$HOME/.tmux.conf"
    symlink "$DOTFILES/linux/wofi/config"                                                        "$HOME/.config/wofi/config"
    symlink "$DOTFILES/linux/wofi/style.css"                                                     "$HOME/.config/wofi/style.css"
    symlink "$DOTFILES/linux/autostart/cliphist-daemon.desktop"                                  "$HOME/.config/autostart/cliphist-daemon.desktop"
    symlink "$DOTFILES/linux/bin/clipboard-picker"                                               "$HOME/bin/clipboard-picker"

    # COSMIC shortcuts — create the dir in case it doesn't exist on a fresh install
    mkdir -p "$HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1"
    symlink "$DOTFILES/linux/cosmic/shortcuts/custom"                                            "$HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom"
}

# =============================================================================
# Run
# =============================================================================
case "$OS" in
    macos)
        install_macos
        install_devops_macos
        install_common
        create_common_symlinks
        create_macos_symlinks
        ;;
    popos|linux)
        install_linux
        install_devops_linux
        install_common
        create_common_symlinks
        create_linux_symlinks
        ;;
esac

echo ""
echo "==> Done! Log out and back in for the shell change to take effect."
