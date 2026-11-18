##################################
# Global ZSH ALIASES AND FUNCTIONS
##################################

##################################
# PATH
##################################

# macOS Homebrew
if [[ "$(uname -s)" == "Darwin" ]]; then
    [ -d /opt/homebrew/sbin ] && export PATH="/opt/homebrew/sbin:$PATH"
    [ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"
    [ -d /opt/homebrew/opt/mysql-client@8.4/bin ] && export PATH="/opt/homebrew/opt/mysql-client@8.4/bin:$PATH"
fi

# Go: Homebrew's on macOS, the go.dev tarball in /usr/local/go on Linux
if [[ "$(uname -s)" != "Darwin" ]]; then
    [ -d /usr/local/go ] && export PATH="/usr/local/go/bin:$PATH"
fi
[ -d "$HOME/go" ] && export PATH="$HOME/go/bin:$PATH"

# Rust/Cargo
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

# Node
[ -d "$HOME/node_modules" ] && export PATH="$HOME/node_modules:$PATH"

# Local & user bin
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"

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
export PYENV_ROOT="$HOME/.pyenv"

# macOS Ansible fork-safety fix
[[ "$(uname -s)" == "Darwin" ]] && export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

##################################
# Secrets (loaded from files)
##################################
[ -f ~/.claude_api_key ] && export ANTHROPIC_API_KEY=$(cat ~/.claude_api_key)
[ -f ~/.github_token ] && export GITHUB_TOKEN=$(cat ~/.github_token)
[ -f ~/.gemfury_token ] && export FURY_AUTH=$(cat ~/.gemfury_token)

##################################
# Keybindings
##################################
bindkey "^Q" beginning-of-line

##################################
# Functions
##################################

# Python venvs
pyenv_create() { python3 -m venv ~/intact/virtual_envs/$1; }
pyenv_delete() { rm -rf ~/intact/virtual_envs/$1; }
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
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

    export SDKMAN_DIR="$HOME/.sdkman"
    [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
}

# Save Rectangle's current shortcuts into the dotfiles (init.sh imports them on a new Mac)
rectangle-save() {
    local f="$HOME/nodestack/dotfiles/mac/rectangle.plist" k
    defaults export com.knollsoft.Rectangle - | plutil -convert xml1 -o "$f" - || return
    for k in "NSStatusItem Preferred Position Item-0" SUHasLaunchedBefore lastVersion; do
        plutil -remove "$k" "$f" 2>/dev/null
    done
    git -C "${f%/mac/*}" --no-pager diff --stat -- mac/rectangle.plist
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

# Kubernetes nodes table: system nodes, then nodegroups, then Karpenter, then the rest,
# with status, age, owner, role, instance type, zone, kubelet version and AMI version. Extra args go to kubectl.
# The AMI ID comes from the managed nodegroup label, or from the Karpenter NodeClaim for Karpenter nodes;
# its version (1.35-v20261112) from the AMI name, read with the cluster's AWS profile. The ID shows if that fails.
kn() {
  # Only the cluster-selection args apply to the NodeClaims and kubeconfig lookups, not node selectors.
  local -a args conn ids
  local i rows amis profile region names
  args=("$@")
  for (( i = 1; i <= ${#args}; i++ )); do
    case "${args[i]}" in
      --context=*|--kubeconfig=*|--cluster=*|--user=*) conn+=("${args[i]}") ;;
      --context|--kubeconfig|--cluster|--user) conn+=("${args[i]}" "${args[i+1]}") ;;
    esac
  done
  rows=$(kubectl get nodes "$@" -o go-template='{{range .items}}{{$l := .metadata.labels}}{{if eq (or (index $l "node-role") "") "system"}}1{{else if index $l "karpenter.sh/nodepool"}}3{{else if index $l "eks.amazonaws.com/nodegroup"}}2{{else}}4{{end}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{range .status.conditions}}{{if eq .type "Ready"}}{{if eq .status "True"}}Ready{{else if eq .status "False"}}NotReady{{else}}Unknown{{end}}{{end}}{{end}}{{if .spec.unschedulable}},SchedulingDisabled{{end}}{{"\t"}}{{.metadata.creationTimestamp}}{{"\t"}}{{if index $l "karpenter.sh/nodepool"}}karpenter{{"\t"}}{{index $l "karpenter.sh/nodepool"}}{{else if index $l "eks.amazonaws.com/nodegroup"}}nodegroup{{"\t"}}{{index $l "eks.amazonaws.com/nodegroup"}}{{else}}other{{"\t"}}-{{end}}{{"\t"}}{{or (index $l "node-role") "-"}}{{"\t"}}{{index $l "node.kubernetes.io/instance-type"}}{{"\t"}}{{index $l "topology.kubernetes.io/zone"}}{{"\t"}}{{.status.nodeInfo.kubeletVersion}}{{"\t"}}{{or (index $l "eks.amazonaws.com/nodegroup-image") "-"}}{{"\n"}}{{end}}' \
    | sort -t $'\t' -k1,1n -k6,6 -k9,9 | cut -f2-) || return
  amis=$(kubectl get nodeclaims "${conn[@]}" -o go-template='{{range .items}}{{.status.nodeName}}{{"\t"}}{{.status.imageID}}{{"\n"}}{{end}}' 2>/dev/null)
  ids=(${(u)$(print -r -- "$rows" | cut -f10; print -r -- "$amis" | cut -f2)})
  ids=(${(M)ids:#ami-*})
  if (( ${#ids} )); then
    profile=$(kubectl config view --minify "${conn[@]}" -o jsonpath='{.users[0].user.exec.env[?(@.name=="AWS_PROFILE")].value}' 2>/dev/null)
    region=$(print -r -- "$rows" | head -1 | cut -f8 | sed 's/[a-z]$//')
    names=$(env ${profile:+AWS_PROFILE=$profile} aws ec2 describe-images --region "$region" --image-ids "${ids[@]}" \
      --query 'Images[].[ImageId,Name]' --output text 2>/dev/null)
  fi
  {
    printf 'NAME\tSTATUS\tAGE\tMANAGED-BY\tGROUP\tROLE\tINSTANCE\tZONE\tVERSION\tAMI\n'
    print -r -- "$rows" | KN_AMIS="$amis" KN_NAMES="$names" _kn_format
  } | column -t -s $'\t'
}

# Turns the creation timestamp in the 3rd column into an age formatted like kubectl's AGE,
# fills a missing AMI ID (10th column) from the "node<TAB>ami" lines in $KN_AMIS, then replaces it with
# the version in its name, from the "ami<TAB>name" lines in $KN_NAMES.
_kn_format() {
  perl -MTime::Local -F'\t' -lane '
    BEGIN {
      %ami  = map { split /\t/ } grep { /\t./ } split /\n/, $ENV{KN_AMIS}  // "";
      %name = map { split /\t/ } grep { /\t./ } split /\n/, $ENV{KN_NAMES} // "";
    }
    if ($F[2] =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)Z$/) {
      my $s = time - timegm($6, $5, $4, $3, $2 - 1, $1);
      my ($m, $h, $d) = (int($s / 60), int($s / 3600), int($s / 86400));
      my $y = int($d / 365);
      sub part { my ($a, $ua, $b, $ub) = @_; $b ? "$a$ua$b$ub" : "$a$ua" }
      $F[2] = $s < 120     ? "${s}s"
            : $m < 10      ? part($m, "m", $s % 60, "s")
            : $h < 3       ? "${m}m"
            : $h < 8       ? part($h, "h", $m % 60, "m")
            : $h < 48      ? "${h}h"
            : $d < 8       ? part($d, "d", $h % 24, "h")
            : $d < 365 * 2 ? "${d}d"
            : $d < 365 * 8 ? part($y, "y", $d % 365, "d")
            :                "${y}y";
    }
    $F[9] = $ami{$F[0]} if $F[9] eq "-" && $ami{$F[0]};
    $F[9] = $1 if ($name{$F[9]} // "") =~ /-(\d+\.\d+-v\d+)$/;
    print join "\t", @F'
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
# Search
##################################
# fd also lists files .gitignore excludes (build output, lambda.zip...) and
# hidden ones; fd's own default skips both. `command fd` for the plain one.
alias fd='fd -u'

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

# DevOps dashboard
alias devops='nvim +DevOps'
