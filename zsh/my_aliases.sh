##################################
# Global ZSH ALIASES AND FUNCTIONS
##################################

# set -x

##################################
# Startup config
##################################
# BIND KEYS
bindkey "^Q" beginning-of-line

# AWS
export AWS_REGION=ca-central-1
export AWS_PAGER=""

# MacOS/Linux specific config
OS=$(uname -a | awk '{print $1}')
if [[ $OS == "Darwin" ]]; then
	# Load MacOS Brew
	[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

	# Ansible issue https://github.com/ansible/ansible/issues/76322
	export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
	[ -d /opt/homebrew/opt/mysql-client@8.0/bin ] && export PATH="/opt/homebrew/opt/mysql-client@8.0/bin:$PATH"
fi

# Nvim default EDITOR
export EDITOR=nvim

# Local bin
[ -d ~/.local/bin/ ] && export PATH="$HOME/.local/bin:$PATH"

# Bash
export SHELLCHECK_OPTS="-e SC2086"

#Github
[ -f ~/.github_token ] && export GITHUB_TOKEN=$(cat ~/.github_token)

# Golang
export GO_ENV=local
[ -d ~/go ] && export PATH="$HOME/go/bin:$PATH"
# [ -d ~/.local/bin/go ] && export PATH="$HOME/.local/bin/go/bin:$PATH"
[ -d /usr/local/go/ ] && export PATH=$PATH:/usr/local/go/bin

# Load RUST/Cargo apps
[ -d ~/.cargo/bin ] && export PATH="$HOME/.cargo/bin:$PATH"

# Load node
[ -d ~/node_modules ] && export PATH="$HOME/node_modules:$PATH"

# Load Postgresql client
[ -d /usr/local/opt/libpq/bin ] && export PATH="/usr/local/opt/libpq/bin:$PATH"

# Load Ruby/Gem
if [ -d /usr/local/opt/ruby/bin ]; then
	export PATH="/usr/local/opt/ruby/bin:$PATH"

	GEM_BIN=$(which gem)

	if [ -f "$GEM_BIN" ]; then
		BIN_VERSION=$(find -d ~/.gem/ruby -depth 1 | rev | cut -d"/" -f1 | rev | head -n 1)
		[ -d ~/.gem/ruby/${BIN_VERSION}/bin ] && export PATH="${HOME}/.gem/ruby/${BIN_VERSION}/bin:${PATH}"
	fi
fi

# Hashivault token
# export VAULT_SKIP_VERIFY=true
# export VAULT_TOKEN=$(cat ~/.vault_token)
# export TF_VAR_VAULT_TOKEN=${VAULT_TOKEN}

##################################
# Functions
##################################

pyenv_create() {
	python3 -m venv ~/intact/virtual_envs/$1
}

dev_UP() {
	# NVM (npm package manager)
	export NVM_DIR="$HOME/.nvm"
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
	[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

	# SDKMAN
	export SDKMAN_DIR="$HOME/.sdkman"
	[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

	# Python pyenv
	# export PYENV_ROOT="$HOME/.pyenv"
	# [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
	# eval "$(pyenv init - zsh)"
	# eval "$(pyenv virtualenv-init -)"
}

pyenv_delete() {
	rm -rf ~/intact/virtual_envs/$1
}

pyenv_source() {
	if [ -z "$1" ]; then
		eza ~/intact/virtual_envs/
	else
		source ~/intact/virtual_envs/$1/bin/activate
		export VIM_PYTHON_VENV=~/intact/virtual_envs/$1/bin
	fi
}

tolower() {
	echo "$1" | awk '{print tolower($0)}'
}

toupper() {
	echo "$1" | awk '{print toupper($0)}'
}

gitjpush() {
	git add -A && git commit -m "$1" && git push
}

# Television
tvcd() {
	cd ~
	TV_FILES=$(tv files)
	cd $(dirname $TV_FILES)
}

tvvim() {
	cd ~
	TV_FILES=$(tv files)
	cd $(dirname $TV_FILES)
	nvim $(basename $TV_FILES)
}

#Code
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

#Shortcuts
alias v='nvim'
alias vim='nvim'
alias bim='nvim'
alias cim='nvim'
alias vimo='nvim -O'
alias vimdiff='nvim -d'
alias myzsh='mybash'
alias mybash='vim ~/.my_aliases.sh'
alias vimzsh='vim ~/.zshrc'
alias vimkitty='vim ~/.config/kitty/kitty.conf'
alias vimtmux='vim ~/.tmux.conf'
alias mytmux='vim ~/.tmux.conf'

#Shortcut CD
alias cdold='cd $OLDPWD'
alias cddotfiles='cd ~/nodestack/dotfiles'

#Alias LS
alias kk='ll'
alias ll='eza -lgHF -s type'
alias lll='eza -lgHF -s type'
alias lla='eza -lagHF -s type'
alias lt='eza -lgHF --tree -s type'
alias ltgit='eza -lgHF --tree --git-ignore -s type'
alias lt2='eza -lgHF --tree -L2 -s type'
alias lt3='eza -lgHF --tree -L3 -s type'
alias lt4='eza -lgHF --tree -L4 -s type'

#SUDO Shortcuts
alias boss='sudo su -'
alias ssu='sudo su -'
alias apt='sudo apt'
alias podman='sudo podman'
alias podman-compose='sudo podman-compose'
