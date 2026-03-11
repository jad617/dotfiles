# dotfiles

Cross-platform dotfiles for macOS and Pop!_OS (COSMIC desktop), managed as symlinks from this repo.

## Bootstrap

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jad617/dotfiles/main/init.sh)
```

Idempotent — safe to re-run. Installs packages, creates symlinks, and configures the system.

## Structure

```
dotfiles/
├── editors/nvim/          Neovim config
├── linux/
│   ├── autostart/         XDG autostart entries (cliphist daemon)
│   ├── bin/               Helper scripts (clipboard-picker)
│   ├── cosmic/shortcuts/  COSMIC desktop keyboard shortcuts (RON)
│   ├── keyd/              Kernel-level key remapping (capslock → a)
│   └── wofi/              Wofi launcher config + style
├── mac/
│   └── capslock.plist     hidutil launchd plist (capslock → a)
├── notes/                 Reference snippets (AWS, Terraform, etc.)
├── shell/
│   ├── prompt/ohmyposh/   Oh-My-Posh theme (zsh.toml)
│   └── zsh/               zshrc, my_aliases.sh
└── terminal/
    ├── ghostty/           Ghostty config
    ├── iterm2/            iTerm2 profiles + color schemes
    ├── kitty/             Kitty config (cross-platform font split)
    ├── tmux/              Tmux configs (Linux / macOS)
    ├── wezterm/           WezTerm config
    └── zellij/            Zellij config + layouts
```

## Key features

- **Clipboard**: cliphist + wofi (Linux) / Maccy (macOS), floating over tiling
- **Capslock → `a`**: keyd on Linux, hidutil launchd on macOS
- **Prompt**: Oh-My-Posh with session-scoped Azure segment
- **Shell**: unified zshrc + aliases for both platforms, lazy-loaded kubectl/pyenv/zoxide
- **Copy/paste**: Alt+C / Alt+V mapped to Ctrl+C / Ctrl+V via COSMIC shortcuts + wtype
