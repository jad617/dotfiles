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
A failed brew install / upgrade is reported as a warning and the run carries on.

On a Mac without admin rights (`/Applications` not writable), brew casks and WezTerm.app go to
`~/Applications`. Casks already in `/Applications` are upgraded in place when the terminal has the
App Management permission (System Settings → Privacy & Security); otherwise (e.g. on a
managed Mac) they're left as they are and listed under "Kept" in the summary.

`--upgrade` on macOS also upgrades every other Homebrew formula and cask you installed yourself
(omitted apps and pinned formulae excepted), then runs `brew cleanup`. Replaced apps are
uninstalled for you (tfsec → trivy, mysql-client@8.0 → @8.4, the azure-cli formula → its cask).

On macOS the links step also applies system settings: the `MACOS_DEFAULTS` table in `init.sh`
(Dock, dark mode, Finder, clock, trackpad, window tiling off) plus the keyboard shortcuts and layouts
in `mac/`. Only values that differ are written; pinned Dock apps are left alone.
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
│   ├── capslock.plist     hidutil launchd plist (capslock → a)
│   ├── input-sources.plist     Keyboard layouts (Canadian, Canadian French PC)
│   ├── symbolichotkeys.plist   System keyboard shortcuts (which ones are disabled)
│   └── rectangle.plist    Rectangle shortcuts; imported when Rectangle has none, update with `rectangle-save`
├── nixos/                 NixOS + Hyprland + Caelestia (see nixos/README.md)
│   ├── install-from-linux.sh   Install NixOS from another Linux or a live USB (guided)
│   ├── init.sh            On NixOS: link the configs, rebuild the system
│   ├── flake.nix, configuration.nix, gpu.nix   The system (gpu.nix: NVIDIA / AMD drivers)
│   ├── hosts/             Per-host config (hashirama, utm = arm64 VM on a Mac)
│   ├── config/            Hyprland, Caelestia, GTK configs (linked into ~/.config)
│   ├── lib/               Helpers the two scripts above use (Wi-Fi / SSH copy, links, GPU detection)
│   ├── vm/                macOS: create a UTM VM and install the config into it
│   └── docs/              INSTALL.md (the installer), ENCRYPTION.md (disk encryption plan)
├── notes/                 Reference snippets (AWS, Terraform, etc.)
├── shell/
│   ├── prompt/ohmyposh/   Oh-My-Posh theme (zsh.toml)
│   └── zsh/               zshrc, my_aliases.sh
└── terminal/
    ├── ghostty/           Ghostty config
    ├── kitty/             Kitty config (cross-platform font split)
    ├── tmux/              Tmux configs (Linux / macOS)
    ├── wezterm/           WezTerm config
    └── zellij/            Zellij config + layouts
```

## Key features

- **Clipboard**: cliphist + wofi (Linux) / Maccy (macOS), floating over tiling
- **Capslock → `a`**: keyd on Linux, hidutil launchd on macOS
- **Gaming (Pop!_OS, NixOS)**: Steam, plus the NVIDIA driver picked from the detected card (580 for GTX 9xx / 10xx, current for newer); AMD uses Mesa
- **Prompt**: Oh-My-Posh with session-scoped Azure segment
- **Shell**: unified zshrc + aliases for both platforms, lazy-loaded kubectl/pyenv/zoxide
- **Copy/paste**: Alt+C / Alt+V mapped to Ctrl+C / Ctrl+V via COSMIC shortcuts + wtype
