# Tools
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k

# Fonts
# https://fonts.google.com/download?family=Cousine
# https://fonts.google.com/download?family=Roboto+Mono

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
  watch

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# DevOps
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" && sudo installer -pkg AWSCLIV2.pkg -target / && rm -f AWSCLIV2.pkg

brew tap hashicorp/tap
brew install \
  hashicorp/tap/terraform \
  terraform-docs \
  ansible \
  kubectl \
  mysql-client@8.0

# UI
brew install --cask rectangle
brew install \
  maccy \
  television

git clone https://gitlab.com/dwt1/shell-color-scripts.git /tmp/color
cd /tmp/color
sudo make install
cd ~

# Pip
pip3 upgrade pip --break-system-packages
pip3 install neovim --break-system-packages

# Configs
mkdir -p ~/.config/kitty/
mkdir -p ~/.config/television/

mkdir -p ~/nodestack/
git clone https://github.com/jad617/dotfiles.git ~/nodestack/dotfiles

ln -s -f ~/nodestack/dotfiles/tmux/macos_tmux.conf ~/.tmux.conf
ln -s -f ~/nodestack/dotfiles/zsh/my_aliases.sh ~/.my_aliases.sh
ln -s -f ~/nodestack/dotfiles/terminal/kitty/kitty.conf ~/.config/kitty/kitty.conf
ln -s -f ~/nodestack/dotfiles/zsh/zshrc_macos ~/.zshrc
ln -s -f ~/nodestack/dotfiles/zshNvim ~/.config/nvim
ln -s -f ~/nodestack/dotfiles/zsh/p10k.zsh ~/.p10k.zsh
ln -s -f  ~/nodestack/dotfiles/zsh/television.config.toml ~/.config/television/config.toml
