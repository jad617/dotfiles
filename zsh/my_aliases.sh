#===========Custom run after running cd ============

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

# if [ -n "$WSL_DISTRO_NAME" ]
# then
#   export DISPLAY="`sed -n 's/nameserver //p' /etc/resolv.conf`:0"
# fi

# Nvim default EDITOR
export EDITOR=nvim

# Bash
export SHELLCHECK_OPTS="-e SC2086"

#Github
[ -f ~/.github_token ] && export GITHUB_TOKEN=$(cat ~/.github_token)

# Golang
export GO_ENV=local
[ -d ~/go ] && export PATH="$HOME/go/bin:$PATH"

# Load RUST/Cargo apps
[ -d ~/.cargo/bin ] && export PATH="$HOME/.cargo/bin:$PATH"

# Load GOlang bin
[ -d ~/go/bin ] && export PATH="$HOME/go/bin:$PATH"

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

# AWS
export AWS_PROFILE=$(cat ~/.aws_default_profile 2>/dev/null || echo "default")
export AWS_DEFAULT_REGION=ca-central-1
export AWS_PAGER=""

# export TERM=xterm-256color

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
		exa ~/intact/virtual_envs/
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

#Shortcuts only Linux
# OS=$(uname -a | awk '{print $1}')
# if [[ $OS == "Linux" ]]; then
#   alias docker='sudo docker'
# elif [[ $OS == "Darwin" ]]; then
#   export REQUESTS_CA_BUNDLE=~/cert/CA.pem
# fi

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

#i3
alias vimi3='vim ~/.config/i3/initial_config'
alias vimi3_outputs='vim ~/.config/i3/ouput_config'
alias vimi3_full='vim ~/.config/i3/config'

#Shortcut CD
alias cdold='cd $OLDPWD'
alias cddotfiles='cd ~/nodestack/dotfiles'
alias cdlazyvim='cd ~/nodestack/dotfiles/lazyvim/'
alias vimlazyvim='cd ~/nodestack/dotfiles/lazyvim && vim init.lua'
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
alias cll='clear && exa -lgHF'
alias kk='ll'
alias ll='exa -lgHF -s type'
alias lll='exa -lgHF -s type'
alias lla='exa -lagHF -s type'
alias clt='clear && exa -lgHF --tree -s type'
alias clt2='clear && exa -lgHF --tree -L2 -s type'
alias clt3='clear && exa -lgHF --tree -L3 -s type'
alias clt4='clear && exa -lgHF --tree -L4 -s type'
alias lt='exa -lgHF --tree -s type'
alias ltgit='exa -lgHF --tree --git-ignore -s type'
alias lt2='exa -lgHF --tree -L2 -s type'
alias lt3='exa -lgHF --tree -L3 -s type'
alias lt4='exa -lgHF --tree -L4 -s type'

#SUDO Shortcuts
alias boss='sudo su -'
alias ssu='sudo su -'
alias mtr='sudo mtr'
alias apt='sudo apt'

# alias aws='aws --no-verify-ssl'

# Extras
alias cdbnc='cd ~/bnc'
alias cdtransaction='cd ~/bnc/APP7363-DTB-transaction/'
alias cdaccount='cd ~/bnc/APP6157-DTB-account/'
