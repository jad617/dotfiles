# Tools
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k

brew install zsh-syntax-highlighting
brew install htop
brew install wget
brew install luajit
brew install pwgen

# DevOps
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install terraform-docs
brew install ansible
brew install kubectl
brew install mysql-client@8.0

# UI
brew install --cask rectangle
brew install maccy

# Pip
pip3 upgrade pip --break-system-packages
pip3 install neovim --break-system-packages

# Configs
mkdir -p ~/.config/kitty/
mkdir -p ~/nodestack/
git clone https://github.com/jad617/dotfiles.git ~/nodestack/dotfiles


ln -s -f ~/nodestack/dotfiles/tmux/macos_tmux.conf ~/.tmux.conf
ln -s -f ~/nodestack/dotfiles/zsh/my_aliases.sh ~/.my_aliases.sh
ln -s -f ~/nodestack/dotfiles/terminal/kitty/kitty.conf ~/.config/kitty/kitty.conf
ln -s -f ~/nodestack/dotfiles/zsh/zshrc_macos ~/.zshrc
ln -s -f ~/nodestack/dotfiles/zshNvim ~/.config/nvim
ln -s -f ~/nodestack/dotfiles/zsh/p10k.zsh ~/.p10k.zsh
