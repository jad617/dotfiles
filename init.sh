#!/usr/bin/env bash
# =============================================================================
# Idempotent dotfiles bootstrap — macOS & Pop!_OS
#
# Usage:
#   ./init.sh             install what's missing; never upgrades (default)
#   ./init.sh --upgrade   also upgrade everything it manages to the latest
#
# On a fresh machine:
#   bash <(curl -fsSL https://raw.githubusercontent.com/jad617/dotfiles/main/init.sh)
#
# Safe to re-run: every step checks the current state first.
# =============================================================================
set -euo pipefail

usage() { sed -n '4,7p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//' || true; }

UPGRADE=false
case "${1:-}" in
"" | install | --install) ;;
upgrade | --upgrade | -u) UPGRADE=true ;;
-h | --help)
    usage
    exit 0
    ;;
*)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
esac

# Run from a checkout → use it. Piped from curl (`bash <(curl …)`) the script
# lives in /dev/fd, so fall back to the standard clone location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -d "$SCRIPT_DIR/.git" && -f "$SCRIPT_DIR/init.sh" ]]; then
    DOTFILES="$SCRIPT_DIR"
else
    DOTFILES="$HOME/nodestack/dotfiles"
fi

# -----------------------------------------------------------------------------
# Detect OS
# -----------------------------------------------------------------------------
OS=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
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
    elif [[ "${ID:-}" == "pop" ]]; then
        OS="popos"
    else
        OS="linux"
    fi
fi

[[ -z "$OS" ]] && {
    echo "Unsupported OS: $OSTYPE"
    exit 1
}
echo "==> Detected OS: $OS · mode: $($UPGRADE && echo upgrade || echo install)"


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
symlink() {
    local src=$1 dst=$2
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        return
    fi
    mkdir -p "$(dirname "$dst")"
    # Remove dst unconditionally — ln -sf creates inside an existing
    # directory (real or symlink-to-dir) rather than replacing it.
    rm -rf "$dst"
    ln -s "$src" "$dst"
    echo "  linked: $dst"
}

clone_if_missing() {
    local repo=$1 dest=$2
    if [[ ! -d "$dest" ]]; then
        git clone "$repo" "$dest"
    fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

# True when a tool should be (re)installed: it's missing, or we're upgrading.
want() { ! cmd_exists "$1" || $UPGRADE; }

# Latest release tag of a GitHub repo, e.g. gh_latest jesseduffield/lazygit → v0.55.1
gh_latest() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name'; }

# apt: install only the missing packages (plain `apt install` would also
# upgrade installed ones); in upgrade mode install + upgrade them all.
apt_install() {
    local missing=() p
    for p in "$@"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
    done
    if $UPGRADE; then
        sudo apt install -y "$@"
    elif ((${#missing[@]})); then
        sudo apt install -y "${missing[@]}"
    fi
}

# Homebrew: install only what's missing (`brew install` would upgrade or
# complain about installed ones); in upgrade mode install + upgrade them all.
# Names must be canonical (no aliases), e.g. kubernetes-cli not kubectl.
brew_install() {
    local kind=--formula
    if [[ "$1" == --cask ]]; then kind=--cask; shift; fi
    if $UPGRADE; then
        brew install "$kind" "$@"
        brew upgrade "$kind" "$@" || true
        return
    fi
    local installed missing=() p
    installed=$(brew list "$kind" -1)
    for p in "$@"; do
        grep -qx "${p##*/}" <<<"$installed" || missing+=("$p")
    done
    if ((${#missing[@]})); then brew install "$kind" "${missing[@]}"; fi
}

# Install / upgrade a single binary from a URL into /usr/local/bin.
install_bin() {
    local name=$1 url=$2
    sudo curl -fsSL "$url" -o "/usr/local/bin/$name"
    sudo chmod +x "/usr/local/bin/$name"
}

# Global npm package (Linux needs sudo: NodeSource node lives in /usr).
npm_global() {
    local bin=$1 pkg=$2
    want "$bin" || return 0
    if [[ "$OS" == "macos" ]]; then npm install -g "$pkg@latest"; else sudo npm install -g "$pkg@latest"; fi
}

# -----------------------------------------------------------------------------
# fzf — git checkout in ~/.fzf + its own installer (same on both OS), which
# generates ~/.fzf.zsh sourced by zshrc. Not brew/apt, to match existing setups.
# -----------------------------------------------------------------------------
install_fzf() {
    local flags=(--key-bindings --completion --no-update-rc --no-fish)
    if [[ ! -d "$HOME/.fzf" ]]; then
        echo "==> Installing fzf"
        git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
        "$HOME/.fzf/install" "${flags[@]}"
    elif $UPGRADE; then
        echo "==> Upgrading fzf"
        git -C "$HOME/.fzf" pull --ff-only
        "$HOME/.fzf/install" "${flags[@]}"
    fi
}

# -----------------------------------------------------------------------------
# Go — official tarball (Linux; macOS uses brew)
# -----------------------------------------------------------------------------
install_go() {
    local go_bin="/usr/local/go/bin/go"
    [[ -x "$go_bin" ]] && ! $UPGRADE && return

    local arch
    if [[ "$(uname -m)" == "arm64" ]]; then arch="arm64"; else arch="amd64"; fi
    local latest
    latest=$(curl -fsSL "https://go.dev/dl/?mode=json" | jq -r '.[0].version')
    if [[ -x "$go_bin" ]] && [[ "$($go_bin version | awk '{print $3}')" == "$latest" ]]; then
        return
    fi

    echo "==> Installing Go $latest"
    local archive="${latest}.linux-${arch}.tar.gz"
    curl -fsSL "https://go.dev/dl/${archive}" -o "/tmp/${archive}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${archive}"
    rm "/tmp/${archive}"
}

# -----------------------------------------------------------------------------
# Clone dotfiles
# -----------------------------------------------------------------------------
mkdir -p ~/nodestack
if [[ "$OS" != "macos" ]] && ! cmd_exists git; then
    sudo apt update && sudo apt install -y git
fi
clone_if_missing "https://github.com/jad617/dotfiles.git" "$DOTFILES"

# =============================================================================
# macOS — base tools
# =============================================================================
install_macos() {
    echo "==> macOS base packages"

    if ! cmd_exists brew; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    brew_install \
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
        jandedobbeleer/oh-my-posh/oh-my-posh \
        zellij \
        node \
        go \
        uv \
        tree-sitter-cli \
        jq \
        yq \
        lazygit \
        btop \
        pipx \
        p7zip \
        nmap \
        mtr \
        ipcalc

    local casks=(wezterm@nightly font-meslo-lg-nerd-font maccy)
    [[ -d "/Applications/Rectangle.app" ]] || casks+=(rectangle)
    brew_install --cask "${casks[@]}"
    # Self-updating / nightly casks are only upgraded with --greedy.
    if $UPGRADE; then brew upgrade --cask --greedy "${casks[@]}" || true; fi

    install_fzf
}

# =============================================================================
# Linux — base tools
# =============================================================================
install_linux() {
    echo "==> Linux base packages"

    sudo apt update
    apt_install \
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
        btop \
        pipx \
        p7zip-full \
        nmap \
        mtr-tiny \
        ipcalc \
        ca-certificates \
        gnupg

    mkdir -p ~/bin ~/.local/bin

    # Debian/Ubuntu ship fd and bat as fdfind / batcat; expose the usual names.
    cmd_exists fd || ln -sf "$(command -v fdfind)" ~/.local/bin/fd
    cmd_exists bat || ln -sf "$(command -v batcat)" ~/.local/bin/bat

    # Node.js LTS from NodeSource — apt's nodejs is too old (Copilot CLI needs ≥ 22)
    local node_major=0
    cmd_exists node && node_major=$(node -p 'process.versions.node.split(".")[0]')
    if ((node_major < 22)); then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt install -y nodejs
    elif $UPGRADE; then
        apt_install nodejs
    fi

    install_fzf

    # eza (macOS: brew)
    if want eza; then
        local eza_ver
        eza_ver=$(gh_latest eza-community/eza)
        curl -fsSL "https://github.com/eza-community/eza/releases/download/${eza_ver}/eza_x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
        sudo install /tmp/eza /usr/local/bin/
        rm -f /tmp/eza
    fi

    # zoxide (macOS: brew) — installer overwrites in place
    if want zoxide; then
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi

    # uv — Python package manager (macOS: brew)
    if ! cmd_exists uv; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
    elif $UPGRADE; then
        uv self update
    fi

    # oh-my-posh — installer overwrites in place
    if want oh-my-posh; then
        curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin
    fi

    # pyenv (macOS: brew) — check directory, not command, since pyenv may not be in PATH yet
    if [[ ! -d "$HOME/.pyenv" ]]; then
        curl https://pyenv.run | bash
    elif $UPGRADE; then
        "$HOME/.pyenv/bin/pyenv" update
    fi

    # wezterm (apt repo)
    if [[ ! -f /etc/apt/sources.list.d/wezterm.list ]]; then
        curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
        echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
        sudo apt update
    fi
    apt_install wezterm-nightly

    # zellij (macOS: brew)
    if want zellij; then
        local zj_ver
        zj_ver=$(gh_latest zellij-org/zellij)
        curl -fsSL "https://github.com/zellij-org/zellij/releases/download/${zj_ver}/zellij-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
        sudo install /tmp/zellij /usr/local/bin/
        rm -f /tmp/zellij
    fi

    # lazygit (macOS: brew)
    if want lazygit; then
        local lg_ver
        lg_ver=$(gh_latest jesseduffield/lazygit)
        curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${lg_ver}/lazygit_${lg_ver#v}_Linux_x86_64.tar.gz" | tar -xz -C /tmp lazygit
        sudo install /tmp/lazygit /usr/local/bin/
        rm -f /tmp/lazygit
    fi

    # yq — mikefarah's Go yq, same as brew (apt's yq is a different tool)
    if want yq; then
        install_bin yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    fi

    install_go
    export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

    # cliphist — needs Go (macOS: uses Maccy instead)
    if want cliphist; then
        go install go.senan.xyz/cliphist@latest
    fi

    # Nerd Font — MesloLGS NF
    if [[ ! -d "$HOME/.local/share/fonts/MesloLGS" ]]; then
        echo "==> Installing MesloLGS NF font"
        local font_dir="$HOME/.local/share/fonts/MesloLGS"
        mkdir -p "$font_dir"
        for variant in "Regular" "Bold" "Italic" "Bold%20Italic"; do
            curl -fsSL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${variant}.ttf" \
                -o "$font_dir/MesloLGS NF ${variant//%20/ }.ttf"
        done
        fc-cache -f "$font_dir"
    fi
}

# =============================================================================
# DevOps tools — macOS
# =============================================================================
install_devops_macos() {
    echo "==> macOS DevOps tools"

    # Neovim nightly (brew HEAD build)
    if ! brew list --formula neovim &>/dev/null; then
        brew install --HEAD neovim
    elif $UPGRADE; then
        brew upgrade --fetch-HEAD neovim || true
    fi

    # AWS CLI
    if want aws; then
        curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
        sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
        rm -f /tmp/AWSCLIV2.pkg
    fi

    brew_install \
        hashicorp/tap/terraform \
        hashicorp/tap/vault \
        terraform-docs \
        ansible \
        kubernetes-cli \
        derailed/k9s/k9s \
        mysql-client@8.0 \
        helm \
        gh \
        azure-cli \
        eksctl \
        argocd \
        actionlint \
        yamllint \
        tfsec \
        maven \
        dotnet \
        dotnet@8 \
        deno

    # Claude CLI — native installer (npm install is deprecated); self-updating
    if ! cmd_exists claude; then
        curl -fsSL https://claude.ai/install.sh | bash
    elif $UPGRADE; then
        claude update || true
    fi

    npm_global copilot @github/copilot
}

# =============================================================================
# DevOps tools — Linux
# =============================================================================
install_devops_linux() {
    echo "==> Linux DevOps tools"

    # Neovim nightly (macOS: brew --HEAD neovim)
    if want nvim; then
        echo "==> Installing Neovim nightly"
        curl -fsSL https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz -o /tmp/nvim.tar.gz
        sudo rm -rf /opt/nvim-linux-x86_64
        sudo tar -xzf /tmp/nvim.tar.gz -C /opt/
        sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
        rm /tmp/nvim.tar.gz
    fi

    # AWS CLI
    if want aws; then
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
        unzip -qo /tmp/awscliv2.zip -d /tmp
        sudo /tmp/aws/install --update
        rm -rf /tmp/aws /tmp/awscliv2.zip
    fi

    # HashiCorp apt repo (terraform + vault)
    if [[ ! -f /etc/apt/sources.list.d/hashicorp.list ]]; then
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --batch --no-tty --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
            sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update
    fi

    # GitHub CLI apt repo
    if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
        sudo apt update
    fi

    # Azure CLI — Microsoft's script adds their apt repo, then apt keeps it current
    if ! cmd_exists az; then
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    fi

    # apt-managed: terraform, vault, gh, az, ansible, yamllint, maven, .NET 8 SDK
    apt_install terraform vault gh azure-cli ansible yamllint maven dotnet-sdk-8.0

    # kubectl
    if want kubectl; then
        install_bin kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    fi

    # helm — v4, matching brew
    if want helm; then
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
    fi

    # k9s (macOS: brew)
    if want k9s; then
        local k9s_ver
        k9s_ver=$(gh_latest derailed/k9s)
        curl -fsSL "https://github.com/derailed/k9s/releases/download/${k9s_ver}/k9s_Linux_amd64.tar.gz" | tar -xz -C /tmp k9s
        sudo install /tmp/k9s /usr/local/bin/
        rm -f /tmp/k9s
    fi

    # eksctl
    if want eksctl; then
        curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar -xz -C /tmp
        sudo install /tmp/eksctl /usr/local/bin/
        rm -f /tmp/eksctl
    fi

    # argocd
    if want argocd; then
        install_bin argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    fi

    # actionlint
    if want actionlint; then
        (cd /tmp && bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash))
        sudo install /tmp/actionlint /usr/local/bin/
        rm -f /tmp/actionlint
    fi

    # tfsec
    if want tfsec; then
        install_bin tfsec https://github.com/aquasecurity/tfsec/releases/latest/download/tfsec-linux-amd64
    fi

    # deno → ~/.local/bin (already on PATH via my_aliases.sh)
    if ! cmd_exists deno; then
        curl -fsSL https://deno.land/install.sh | DENO_INSTALL="$HOME/.local" sh -s -- -y --no-modify-path
    elif $UPGRADE; then
        deno upgrade
    fi

    # Claude CLI — native installer (npm install is deprecated); self-updating
    if ! cmd_exists claude; then
        curl -fsSL https://claude.ai/install.sh | bash
    elif $UPGRADE; then
        claude update || true
    fi

    # Copilot CLI (needs Node ≥ 22 — installed in install_linux)
    npm_global copilot @github/copilot
    # tree-sitter CLI — required by nvim-treesitter (main branch) for parser compilation
    npm_global tree-sitter tree-sitter-cli

    # keyd — kernel-level key remapping (Wayland-compatible, macOS uses hidutil instead)
    # Not in apt; build from source
    if ! cmd_exists keyd; then
        apt_install gcc make libevdev-dev libudev-dev
        rm -rf /tmp/keyd
        git clone https://github.com/rvaiya/keyd.git /tmp/keyd
        make -C /tmp/keyd
        sudo make -C /tmp/keyd install
        rm -rf /tmp/keyd
    fi
    sudo mkdir -p /etc/keyd
    sudo ln -sf "$DOTFILES/linux/keyd/default.conf" /etc/keyd/default.conf
    systemctl is-enabled --quiet keyd 2>/dev/null && systemctl is-active --quiet keyd ||
        sudo systemctl enable --now keyd
}

# =============================================================================
# Common — after OS + DevOps packages
# =============================================================================
install_common() {
    # Set zsh as default shell
    if [[ "$SHELL" != "$(command -v zsh)" ]]; then
        echo "==> Setting zsh as default shell"
        chsh -s "$(command -v zsh)"
    fi

    # Tmux Plugin Manager
    clone_if_missing "https://github.com/tmux-plugins/tpm" "$HOME/.tmux/plugins/tpm"
    if $UPGRADE; then git -C "$HOME/.tmux/plugins/tpm" pull --ff-only; fi

    # Neovim Python support
    if ! python3 -c "import pynvim" &>/dev/null || $UPGRADE; then
        pip3 install -U pynvim --break-system-packages 2>/dev/null || pip3 install -U pynvim || true
    fi

    # Zsh completions — fetched from upstream, not tracked in dotfiles
    local tf_comp_root="$HOME/.config/zsh-completion"
    local tf_comp="$tf_comp_root/terraform/_terraform"
    # Remove broken symlink that would block directory creation
    if [[ -L "$tf_comp_root" && ! -e "$tf_comp_root" ]]; then rm "$tf_comp_root"; fi
    if [[ ! -s "$tf_comp" ]] || $UPGRADE; then
        echo "==> Fetching zsh completions"
        mkdir -p "$(dirname "$tf_comp")"
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/terraform/_terraform -o "$tf_comp"
    fi
}

# =============================================================================
# Symlinks — common to both OS
# =============================================================================
create_common_symlinks() {
    echo "==> Symlinks"
    symlink "$DOTFILES/shell/zsh/my_aliases.sh" "$HOME/.my_aliases.sh"
    symlink "$DOTFILES/terminal/wezterm/wezterm.lua" "$HOME/.wezterm.lua"
    symlink "$DOTFILES/editors/nvim" "$HOME/.config/nvim"
    symlink "$DOTFILES/shell/prompt/ohmyposh" "$HOME/.config/ohmyposh"
    symlink "$DOTFILES/terminal/zellij" "$HOME/.config/zellij"
    symlink "$DOTFILES/terminal/kitty" "$HOME/.config/kitty"
}

# =============================================================================
# Symlinks — macOS only
# =============================================================================
create_macos_symlinks() {
    symlink "$DOTFILES/shell/zsh/zshrc" "$HOME/.zshrc"
    symlink "$DOTFILES/terminal/tmux/macos_tmux.conf" "$HOME/.tmux.conf"

    # Caps Lock → letter 'a' via hidutil (persisted through launchd)
    local plist_dst="$HOME/Library/LaunchAgents/com.user.capslock.plist"
    symlink "$DOTFILES/mac/capslock.plist" "$plist_dst"
    if ! launchctl print "gui/$(id -u)/com.user.capslock" &>/dev/null; then
        launchctl bootstrap "gui/$(id -u)" "$plist_dst"
        echo "  capslock remapped to 'a' (hidutil)"
    fi
}

# =============================================================================
# Symlinks — Linux (Pop!_OS) only
# =============================================================================
create_linux_symlinks() {
    symlink "$DOTFILES/shell/zsh/zshrc" "$HOME/.zshrc"
    symlink "$DOTFILES/terminal/tmux/tmux.conf" "$HOME/.tmux.conf"
    symlink "$DOTFILES/linux/wofi/config" "$HOME/.config/wofi/config"
    symlink "$DOTFILES/linux/wofi/style.css" "$HOME/.config/wofi/style.css"
    symlink "$DOTFILES/linux/autostart/cliphist-daemon.desktop" "$HOME/.config/autostart/cliphist-daemon.desktop"
    symlink "$DOTFILES/linux/bin/clipboard-picker" "$HOME/bin/clipboard-picker"
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
        echo "  updated: $cosmic_shortcuts"
    fi

    # Start cliphist daemon for the current session (autostart handles future logins)
    if cmd_exists wl-paste && [[ -x "$HOME/go/bin/cliphist" ]]; then
        if ! pgrep -f "wl-paste --watch" >/dev/null 2>&1; then
            nohup wl-paste --watch "$HOME/go/bin/cliphist" store &>/dev/null &
            echo "  cliphist daemon started"
        fi
    fi
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
popos | linux)
    install_linux
    install_devops_linux
    install_common
    create_common_symlinks
    create_linux_symlinks
    ;;
esac

echo ""
echo "==> Done! Log out and back in if your default shell changed."
