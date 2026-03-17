# NixOS Hyprland Workstation

Hyprland desktop on NixOS with Catppuccin Macchiato theme.
GTX 1070 · Waybar · Wofi · Mako · Hyprlock · WezTerm · Neovim

---

## Fresh Install

### 1. Install NixOS (minimal ISO)

Boot from the [NixOS minimal ISO](https://nixos.org/download), partition, and install:

```bash
# Partition your disk (example: single EFI + root, adjust to your layout)
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MB 512MB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart primary 512MB 100%

mkfs.fat -F 32 -n boot /dev/sda1
mkfs.ext4 -L nixos /dev/sda2

mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot

# Generate hardware config
nixos-generate-config --root /mnt

# Minimal install (just enough to boot)
nixos-install

reboot
```

### 2. Clone dotfiles & bootstrap

```bash
nix-shell -p git --command "git clone https://github.com/jad617/dotfiles ~/nodestack/dotfiles"
cd ~/nodestack/dotfiles && bash nixos/init.sh
```

First run asks for your timezone once — every run after that is automatic.

### 3. Set a wallpaper

Wallpapers are at `~/Pictures/Wallpapers/`. Edit `~/.config/hypr/hyprpaper.conf` to activate one:

```ini
wallpaper = ,~/Pictures/Wallpapers/quasar.webp        # default
# wallpaper = ,~/Pictures/Wallpapers/kurzgesagt.webp
# wallpaper = ,~/Pictures/Wallpapers/kurzgesagt-galaxies.webp
```

Switch wallpaper at runtime (no restart needed):

```bash
hyprctl hyprpaper wallpaper ",~/Pictures/Wallpapers/kurzgesagt.webp"
```

---

## Daily Usage

### Keybinds

| Key | Action |
|-----|--------|
| `SUPER + Enter` | Open terminal (WezTerm) |
| `SUPER + D` | App launcher (Wofi) |
| `SUPER + E` | File manager (Nautilus) |
| `SUPER + B` | Browser (Firefox) |
| `SUPER + Q` | Close window |
| `SUPER + L` | Lock screen |
| `SUPER + F` | Fullscreen |
| `SUPER + V` | Toggle floating |
| `SUPER + S` | Toggle scratchpad |
| `SUPER + C` | Clipboard history |
| `SUPER + 1-0` | Switch workspace |
| `SUPER + SHIFT + 1-0` | Move window to workspace |
| `SUPER + Arrows / H J K` | Focus window |
| `SUPER + SHIFT + Arrows / H J K L` | Move window |
| `SUPER + ALT + Arrows / H J K L` | Resize window |
| `SUPER + mouse drag` | Move floating window |
| `SUPER + right-click drag` | Resize floating window |
| `Print` | Screenshot selection → clipboard |
| `SHIFT + Print` | Screenshot monitor → clipboard |
| `SUPER + SHIFT + S` | Screenshot selection → clipboard |
| `SUPER + Print` | Screenshot monitor → file |

---

## System Maintenance

### Update everything

```bash
sudo nixos-rebuild switch --upgrade
```

### Update dotfiles config

```bash
git pull && bash nixos/init.sh
```

### Preview changes before applying

```bash
sudo nixos-rebuild dry-activate --upgrade
```

### Roll back if something breaks

```bash
sudo nixos-rebuild switch --rollback
```

Or reboot and select the previous generation from the GRUB menu.

### Clean up old generations (free disk space)

```bash
sudo nix-collect-garbage --delete-older-than 14d
sudo nixos-rebuild boot    # refresh bootloader entries
```

### List generations

```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

---

## Configuration

All config files are symlinked from this repo — edit here, not in `~/.config`.

| Component | Config file |
|-----------|-------------|
| Hyprland  | `nixos/config/hypr/hyprland.conf` |
| Waybar    | `nixos/config/waybar/config.jsonc` + `style.css` |
| Hyprlock  | `nixos/config/hypr/hyprlock.conf` |
| Hypridle  | `nixos/config/hypr/hypridle.conf` |
| Hyprpaper | `nixos/config/hypr/hyprpaper.conf` |
| Mako      | `nixos/config/mako/config` |
| Wofi      | `nixos/config/wofi/config` + `style.css` |
| Neovim    | `editors/nvim/` |
| WezTerm   | `terminal/wezterm/wezterm.lua` |
| Zsh       | `shell/zsh/zshrc` + `my_aliases.sh` |
| NixOS     | `nixos/configuration.nix` (copied to `/etc/nixos/`) |

After editing `configuration.nix`, apply with:

```bash
sudo nixos-rebuild switch
```

---

## Add a Package

Edit `nixos/configuration.nix`, find `environment.systemPackages`, add your package:

```nix
environment.systemPackages = with pkgs; [
  your-package
  # ...
];
```

Then:

```bash
sudo nixos-rebuild switch
```

Search for package names at [search.nixos.org](https://search.nixos.org/packages).

---

## Troubleshooting

### Rebuild failed

```bash
cat /tmp/nixos-rebuild.log
```

### Hyprland won't start

```bash
# Check logs
cat /tmp/hyprland-$(id -u).log

# Try launching manually from TTY
Hyprland
```

### NVIDIA issues

```bash
# Confirm driver is loaded
nvidia-smi

# Check Wayland env vars are set
env | grep -E 'GBM|LIBVA|__GLX|WLR'
```

### Waybar not showing

```bash
# Kill and restart
killall waybar; waybar &

# Check for config errors
waybar --log-level debug
```

### Audio not working

```bash
# Check PipeWire status
systemctl --user status pipewire

# Restart if needed
systemctl --user restart pipewire pipewire-pulse wireplumber

# Open audio mixer
pavucontrol
```

### Reset a single symlink

```bash
# Re-run init.sh — all symlinks are idempotent
bash ~/nodestack/dotfiles/nixos/init.sh
```
