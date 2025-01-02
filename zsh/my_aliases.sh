#===========Custom run after running cd ============
# set -x

# gitGlobal() {
# 	workdir=$(tail -n 1 ~/.git_work_profile 2>/dev/null | cut -d'=' -f2)
#
# 	if [ -f ~/.git_work_profile ] && [[ $PWD == *"$workdir"* ]]; then
# 		for i in $(head -n 2 ~/.git_work_profile); do
# 			git config --global $(echo $i | sed -e 's/=/ /g')
# 			done
# 	else
# 		for i in $(head -n 2 ~/.git_perso_profile); do
# 			git config --global $(echo $i | sed -e 's/=/ /g')
# 		done
# 	fi
# }
#
# chpwd_functions+=(gitGlobal)

#===========Custom============

# BIND KEYS
bindkey "^Q" beginning-of-line

# AWS
export AWS_PROFILE="admin-release"
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

# [ -d ~/usr/local/go ] && export PATH=$PATH:/usr/local/go/bin

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

#ssh auto passphrase
# eval "$(ssh-agent)" &>/dev/null
# cat ~/.ssh/id_rsa | SSH_ASKPASS="$HOME/.passphrase" ssh-add - &>/dev/null
# ssh-add -K > /dev/null 2>/dev/null

#Functions

pyenv_create() {
	python3 -m venv ~/intact/virtual_envs/$1
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

vimpy() {
	file=$1
	is_python=$(
		file $file | grep -o python >/dev/null
		echo $?
	)

	if [ $is_python -eq 0 ]; then
		tmux split-window -h -c '#{pane_current_path}' \; resize-pane -x 50
		tmux select-pane -L
		tmux split-window -v -c '#{pane_current_path}'
		tmux select-pane -U
		tmux resize-pane -y 50
		nvim $file
	fi
}

gitjpush() {
	git add -A && git commit -m "$1" && git push
}

deploy_java() {
	export JAVA_HOME=$(/usr/libexec/java_home -v 1.8.0_201)
	mvn clean package
	mvn exec:java -Dexec.mainClass=""
}

extra() {
	latest_session_id=$(tmux list-sessions | grep extra- | cut -d':' -f1 | tail -n 1 | cut -d'-' -f2)
	new_session=$((latest_session_id+1))
	tmux new-session -d -s extra-$new_session
}

tmux-new-session() {
	tmux new-session -d -s "$1"
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
alias vedit='ansible-vault edit '
# alias git='git --no-pager'
alias gitadd='git add -A'
alias gitcommit='git add -A && git commit -m'
alias gitcheckout='git checkout'
alias gistatus='git status'
alias gitmaster='git checkout master && git pull'
alias gitmain='git checkout main && git pull'
alias gitorigin='git checkout develop'
alias gitproduction='git checkout production'
alias gitpush='git push'
alias gitdiff='git --no-pager diff'
alias gitlog='git log --oneline'
alias gitpull='git pull'
alias gitsubpull='ls | xargs -P10 -I{} git -C {} pull'
alias gitundoall='git reset --hard HEAD'

#Shortcuts
alias zim='nohup zim &'
alias v='nvim'
alias vim='nvim'
alias bim='nvim'
alias cim='nvim'
alias vimo='nvim -O'
alias vimdiff='nvim -d'
alias nvim='clear && nvim'
alias svim='clear && sudo nvim'
alias myzsh='mybash'
alias mybash='vim ~/.my_aliases.sh'
alias sshr='ssh -l root '

# Vim shortcuts
alias vimzsh='vim ~/.zshrc'
alias vimkitty='vim ~/.config/kitty/kitty.conf'
alias vimtmux='vim ~/.tmux.conf'
alias mytmux='vim ~/.tmux.conf'

#i3
alias vimi3='vim ~/.config/i3/initial_config'
alias vimi3_outputs='vim ~/.config/i3/ouput_config'
alias vimi3_full='vim ~/.config/i3/config'

#Shortcut CD
alias cdold='cd $OLDPWD'
alias cddotfiles='cd ~/nodestack/dotfiles'
alias cdlazyvim='cd ~/nodestack/dotfiles/zshNvim/'
alias vimlazyvim='cd ~/nodestack/dotfiles/zshNvim/ && vim init.lua'
alias cdswap='cd ~/.vim/tmp'
alias cdnodestack='cd ~/nodestack'
alias cdopsinc='cd ~/opsinc'
alias cdmgmt='cd ~/nodestack/nodeai/mgmt'
alias cdzim='cd ~/nodestack/zim'

# Alias K8S
# alias kubectl='kubectl 2>/dev/null'

#Shortcut VIM
# alias mynvimrc='vim ~/.config/nvim/init.vim'
alias myvimlua='cd ~/.config/nvim && vim init.lua'
alias mytmux='vim ~/.tmux.conf'

#Alias LS
alias cll='clear && eza -lgHF'
alias kk='ll'
alias ll='eza -lgHF -s type'
alias lll='eza -lgHF -s type'
alias lla='eza -lagHF -s type'
alias clt='clear && eza -lgHF --tree -s type'
alias clt2='clear && eza -lgHF --tree -L2 -s type'
alias clt3='clear && eza -lgHF --tree -L3 -s type'
alias clt4='clear && eza -lgHF --tree -L4 -s type'
alias lt='eza -lgHF --tree -s type'
alias ltgit='eza -lgHF --tree --git-ignore -s type'
alias lt2='eza -lgHF --tree -L2 -s type'
alias lt3='eza -lgHF --tree -L3 -s type'
alias lt4='eza -lgHF --tree -L4 -s type'

#SUDO Shortcuts
alias boss='sudo su -'
alias ssu='sudo su -'
# alias mtr='sudo mtr'
alias apt='sudo apt'
alias podman='sudo podman'
alias podman-compose='sudo podman-compose'

# alias aws='aws --no-verify-ssl'

# Extras
alias cdbnc='cd ~/bnc'
alias cdtransaction='cd ~/bnc/APP7363-DTB-transaction/'
alias cdaccount='cd ~/bnc/APP6157-DTB-account/'
