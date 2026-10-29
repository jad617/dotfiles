# dotfiles

Cross-platform dotfiles for macOS and Pop!_OS (COSMIC desktop), managed as symlinks from this repo.

## Bootstrap

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jad617/dotfiles/main/init.sh)
```

Idempotent — safe to re-run. Installs packages, creates symlinks, and configures the system.
Supports macOS and Ubuntu (incl. Pop!_OS), on x86_64 and arm64.

| Command | What it does |
|---|---|
| `./init.sh` | install what's missing; never upgrades |
| `./init.sh --upgrade` | also upgrade everything it manages (skips tools already at the latest release) |
| `./init.sh --dry-run` | show what would change, change nothing (combine with `--upgrade`) |
| `./init.sh --doctor` | read-only check: PATH shadowing, stale apt keys, broken links, default shell, dirty repo |
| `--only base,devops` / `--skip links` | limit to sections: `base`, `devops`, `shell`, `links` |
| `./init.sh --select` | only edit the app checklist and save it; installs nothing |
| `--omit-app wezterm,dotnet` / `--add-app wezterm` | omit apps / manage them again without the checklist |
| `--yes` | skip the checklist and use the saved choices (automatic without a terminal) |
| `--verbose` | stream command output instead of logging it |

Every interactive run starts with a checklist of every app, one card per source (brew, apt,
cargo, …), pre-set from the saved choices; unchecked apps are omitted. Press `/` to filter by name,
`space` to toggle, `s` for a whole card, `⏎` to continue, `q` to cancel. Omitted apps are saved in
`~/.config/dotfiles/omitted-apps` and skipped on every install and upgrade (never uninstalled);
the summary lists them with the command to add them back.

Output is a compact checklist; full command output goes to `~/.local/state/dotfiles/init-*.log`.
CI (`.github/workflows/init.yml`) runs shellcheck and a fresh install + idempotency check on Ubuntu and macOS.

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
