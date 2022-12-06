#===========Custom============

# if [ -n "$WSL_DISTRO_NAME" ]
# then
#   export DISPLAY="`sed -n 's/nameserver //p' /etc/resolv.conf`:0"
# fi

# Nvim default EDITOR
export EDITOR=nvim

# Golang
export GO_ENV=local
[ -d ~/go ] && export PATH="$HOME/go/bin:$PATH"

# Load RUST/Cargo apps
[ -d ~/.cargo/bin ] && export PATH="$HOME/.cargo/bin:$PATH"

# Load GOlang bin
[ -d ~/go/bin ] && export PATH="$HOME/go/bin:$PATH"

[ -d ~/node_modules ] && export PATH="$HOME/node_modules:$PATH"

#Load MacOs Python
# [ -d ~/.cargo/bin ] && export PATH="$HOME/.cargo/bin:$PATH"


# export AWS_PROFILE=default
export AWS_DEFAULT_REGION=ca-central-1


# export TERM=xterm-256color

#Hashivault token
# export VAULT_TOKEN=$(cat ~/.vault_token)

#ssh auto passphrase
# eval "$(ssh-agent)" &>/dev/null
# cat ~/.ssh/id_rsa | SSH_ASKPASS="$HOME/.passphrase" ssh-add - &>/dev/null
# ssh-add -K > /dev/null 2>/dev/null

#Functions

pyenv_create(){
  python3 -m venv ~/intact/virtual_envs/$1
}

pyenv_delete(){
  rm -rf ~/intact/virtual_envs/$1
}

pyenv_source(){
  if [ -z "$1" ]
  then
    exa  ~/intact/virtual_envs/
  else
    source ~/intact/virtual_envs/$1/bin/activate
    export VIM_PYTHON_VENV=~/intact/virtual_envs/$1/bin
  fi
}

tolower(){
  echo "$1" | awk '{print tolower($0)}'
}

toupper(){
  echo "$1" | awk '{print toupper($0)}'
}

vimpy(){
  file=$1
  is_python=$(file $file | grep -o python > /dev/null; echo $?)

  if [ $is_python -eq 0 ]
  then
    tmux split-window -h -c '#{pane_current_path}' \; resize-pane -x 50
    tmux select-pane -L
    tmux split-window -v -c '#{pane_current_path}'
    tmux select-pane -U
    tmux resize-pane -y 50
    nvim $file
  fi
}

gitjpush(){
  git add -A && git commit -m "$1" && git push
}

deploy_java(){
  export JAVA_HOME=$(/usr/libexec/java_home -v 1.8.0_201)
  mvn clean package
  mvn exec:java -Dexec.mainClass=""
}

#Code
alias vedit='ansible-vault edit '
alias git='git --no-pager'
alias gitadd='git add -A'
alias gitcommit='git add -A && git commit -m'
alias gitcheckout='git checkout'
alias gistatus='git status'
alias gitmaster='git checkout master'
alias gitmain='git checkout main'
alias gitorigin='git checkout develop'
alias gitproduction='git checkout production'
alias gitpush='git push'
alias gitdiff='git --no-pager diff'
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
alias cddotfiles='cd ~/nodestack/dotfiles/'
alias cdswap='cd ~/.vim/tmp'
alias cdnodestack='cd ~/nodestack'
alias cdzim='cd ~/nodestack/zim'

#Shortcut VIM
# alias mynvimrc='vim ~/.config/nvim/init.vim'
alias myvimlua='cd ~/.config/nvim && vim init.lua'
alias mytmux='vim ~/.tmux.conf'

#Alias LS
alias cll='clear && exa -lgHF'
alias kk='ll'
alias ll='exa -lgHF'
alias lll='exa -lgHF'
alias lla='exa -lagHF'
alias clt='clear && exa -lgHF --tree'
alias clt2='clear && exa -lgHF --tree -L2'
alias clt3='clear && exa -lgHF --tree -L3'
alias clt4='clear && exa -lgHF --tree -L4'
alias lt='exa -lgHF --tree'
alias ltgit='exa -lgHF --tree --git-ignore'
alias lt2='exa -lgHF --tree -L2'
alias lt3='exa -lgHF --tree -L3'
alias lt4='exa -lgHF --tree -L4'

#SUDO Shortcuts
alias boss='sudo su -'
alias ssu='sudo su -'
alias mtr='sudo mtr'
alias apt='sudo apt'

# AWS
export AWS_PAGER=""
# alias aws='aws --no-verify-ssl'
