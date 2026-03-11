##################################
# Global ZSH ALIASES AND FUNCTIONS
##################################

##################################
# PATH
##################################

# macOS Homebrew
if [[ "$(uname -s)" == "Darwin" ]]; then
    [ -d /opt/homebrew/bin ]               && export PATH="/opt/homebrew/bin:$PATH"
    [ -d /opt/homebrew/opt/mysql-client@8.0/bin ] && export PATH="/opt/homebrew/opt/mysql-client@8.0/bin:$PATH"
fi

# Go
[ -d /usr/local/go ]       && export PATH="/usr/local/go/bin:$PATH"
[ -d "$HOME/go" ]          && export PATH="$HOME/go/bin:$PATH"

# Rust/Cargo
[ -d "$HOME/.cargo/bin" ]  && export PATH="$HOME/.cargo/bin:$PATH"

# Node
[ -d "$HOME/node_modules" ] && export PATH="$HOME/node_modules:$PATH"

# Local & user bin
[ -d "$HOME/.local/bin" ]  && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ]         && export PATH="$HOME/bin:$PATH"

# Ruby/Gem (macOS only)
if [ -d /usr/local/opt/ruby/bin ]; then
    export PATH="/usr/local/opt/ruby/bin:$PATH"
    if command -v gem &>/dev/null; then
        BIN_VERSION=$(ls ~/.gem/ruby 2>/dev/null | sort -V | tail -n1)
        [ -d "$HOME/.gem/ruby/${BIN_VERSION}/bin" ] && export PATH="${HOME}/.gem/ruby/${BIN_VERSION}/bin:${PATH}"
    fi
fi

# PostgreSQL client (macOS only)
[ -d /usr/local/opt/libpq/bin ] && export PATH="/usr/local/opt/libpq/bin:$PATH"

##################################
# Environment
##################################
export EDITOR=nvim
export GO_ENV=local
export AWS_REGION=ca-central-1
export AWS_PAGER=""
export SHELLCHECK_OPTS="-e SC2086"
export PYENV_ROOT="$HOME/.pyenv"

# macOS Ansible fork-safety fix
[[ "$(uname -s)" == "Darwin" ]] && export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

##################################
# Secrets (loaded from files)
##################################
[ -f ~/.claude_api_key ]  && export ANTHROPIC_API_KEY=$(cat ~/.claude_api_key)
[ -f ~/.github_token ]    && export GITHUB_TOKEN=$(cat ~/.github_token)
[ -f ~/.gemfury_token ]   && export FURY_AUTH=$(cat ~/.gemfury_token)

##################################
# Keybindings
##################################
bindkey "^Q" beginning-of-line

##################################
# Functions
##################################

# Python venvs
pyenv_create() { python3 -m venv ~/intact/virtual_envs/$1; }
pyenv_delete()  { rm -rf ~/intact/virtual_envs/$1; }
pyenv_source() {
    if [ -z "$1" ]; then
        eza ~/intact/virtual_envs/
    else
        source ~/intact/virtual_envs/$1/bin/activate
        export VIM_PYTHON_VENV=~/intact/virtual_envs/$1/bin
    fi
}

# On-demand dev tools (NVM + SDKMAN — lazy loaded to keep shell startup fast)
dev_UP() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ]             && source "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ]    && source "$NVM_DIR/bash_completion"

    export SDKMAN_DIR="$HOME/.sdkman"
    [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
}

# Update zsh completions from upstream sources
update-completions() {
    local tf_comp="$HOME/.config/zsh-completion/terraform/_terraform"
    mkdir -p "$(dirname "$tf_comp")"
    echo "Updating terraform completion..."
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/terraform/_terraform -o "$tf_comp"
    echo "Done. Restart your shell or run: exec zsh"
}

# Azure — track login state via env var so oh-my-posh segment is session-scoped
az() {
    if [[ "$1" == "login" ]]; then
        command az "$@"
        export AZURE_ACTIVE=1
    elif [[ "$1" == "logout" ]]; then
        command az "$@"
        unset AZURE_ACTIVE
    else
        command az "$@"
    fi
}

# Utilities
tolower() { echo "$1" | awk '{print tolower($0)}'; }
toupper() { echo "$1" | awk '{print toupper($0)}'; }
gitjpush() { git add -A && git commit -m "$1" && git push; }

# Television
tvcd() {
    local file
    file=$(cd ~ && tv files)
    cd "$(dirname "$file")"
}
tvvim() {
    local file
    file=$(cd ~ && tv files)
    cd "$(dirname "$file")"
    nvim "$(basename "$file")"
}

##################################
# Git aliases
##################################
alias gitadd='git add -A'
alias gitcommit='git add -A && git commit -m'
alias gitcheckout='git checkout'
alias gistatus='git status'
alias gitmaster='git checkout master && git pull'
alias gitmain='git checkout main && git pull'
alias gitdiff='git --no-pager diff'
alias gitlog='git log --oneline'
alias gitpull='git pull'
alias gitundoall='git reset --hard HEAD'
alias gitclean='git clean -fd'

##################################
# Editor
##################################
alias v='nvim'
alias vim='nvim'
alias bim='nvim'
alias cim='nvim'
alias vimo='nvim -O'
alias vimdiff='nvim -d'
alias mybash='nvim ~/.my_aliases.sh'
alias myzsh='nvim ~/.zshrc'
alias vimkitty='nvim ~/.config/kitty/kitty.conf'
alias vimtmux='nvim ~/.tmux.conf'
alias mytmux='nvim ~/.tmux.conf'

##################################
# Navigation
##################################
alias cdold='cd $OLDPWD'
alias cddotfiles='cd ~/nodestack/dotfiles'

##################################
# ls (eza)
##################################
alias kk='ll'
alias ll='eza -lgHF -s type'
alias lla='eza -lagHF -s type'
alias lt='eza -lgHF --tree -s type'
alias ltgit='eza -lgHF --tree --git-ignore -s type'
alias lt2='eza -lgHF --tree -L2 -s type'
alias lt3='eza -lgHF --tree -L3 -s type'
alias lt4='eza -lgHF --tree -L4 -s type'

##################################
# Sudo shortcuts
##################################
alias boss='sudo su -'
alias ssu='sudo su -'
alias apt='sudo apt'
alias podman='sudo podman'
alias podman-compose='sudo podman-compose'
