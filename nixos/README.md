# NixOS Hyprland Workstation

Hyprland desktop on NixOS with Catppuccin Macchiato theme.
NVIDIA / AMD auto-detected · [Caelestia shell](https://github.com/caelestia-dots/shell) · WezTerm · Neovim

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

(Only for a NixOS installed by hand from the ISO. `install-from-linux.sh` does all of this during
the install: after it, nothing has to be run.)

```bash
nix-shell -p git --command "git clone https://github.com/jad617/dotfiles ~/nodestack/dotfiles"
cd ~/nodestack/dotfiles && bash nixos/init.sh
```

First run asks for your timezone once — every run after that is automatic.

### 3. Set a wallpaper

Wallpapers are at `~/Pictures/Wallpapers/` (default: `quasar.webp`). Caelestia
remembers the last one you picked. Pick one from the launcher (`SUPER + D`, then type
`>wallpaper`) or from a shell:

```bash
caelestia wallpaper -f ~/Pictures/Wallpapers/kurzgesagt.webp
```

### Dual boot from Pop!_OS, on a second disk (no live USB)

`nixos/install-from-linux.sh` installs NixOS from the running Pop!_OS or from a live CD, with
arrow-key menus to pick the disk and the layout: delete some partitions and keep the others, use its
free space, shrink an ext4 partition, or erase it. Pop!_OS's disk can't be picked.

```bash
nixos/install-from-linux.sh
```

After the confirmation the install runs in the background: you can close the terminal and check on it
with `bash nixos/install-from-linux.sh --status` (log: `~/nixos-install-<date>.log`).

Full guide, options and safety checks: **[docs/INSTALL.md](docs/INSTALL.md)**.

Disk encryption and layout (LUKS + Btrfs, Secure Boot + TPM, later move to the NVMe) is planned: **[docs/ENCRYPTION.md](docs/ENCRYPTION.md)**.

### Test in a VM on macOS (`nixos/vm/vm.sh`)

On an Apple Silicon Mac, `nixos/vm/vm.sh` creates an aarch64 NixOS VM in
[UTM](https://mac.getutm.app) and installs the `nixos-arm` host from your checkout,
uncommitted changes included. It needs no admin rights: UTM goes into `~/Applications`
and `qemu` comes from Homebrew.

```bash
nixos/vm/vm.sh install     # download the ISO, create ~/VMs/nixos-dotfiles.utm, install (unattended)
nixos/vm/vm.sh rebuild     # copy this checkout into the VM and run nixos/init.sh
nixos/vm/vm.sh ssh         # SSH in (localhost:2222, your ~/.ssh key)
nixos/vm/vm.sh console     # serial console (localhost:4555)
nixos/vm/vm.sh start | stop | status | destroy
```

In the UTM window the VM logs in by itself and stops at Caelestia's lock screen: unlock as
`jelasmar` (the default `VM_USER`). The first install asks for the
password (or generates one) and keeps it in your macOS login Keychain, never in the repo:
`security find-generic-password -s nixos-vm -w` shows it. `VM_USER`, `VM_PASSWORD`,
`VM_CPUS`, `VM_MEMORY_MB` and `VM_DISK_GB` override the defaults.
If `utmctl` is not allowed to control UTM, the script asks you to press ▶ in UTM.

---

## Daily Usage

### Keybinds

| Key | Action |
|-----|--------|
| `SUPER + Enter` | Open terminal (WezTerm) |
| `SUPER + D` | App launcher (Caelestia) |
| `SUPER + N` | Sidebar: notifications and quick settings (Caelestia) |
| `CTRL + ALT + Delete` | Session menu: lock, log out, reboot, shut down (Caelestia) |
| `SUPER + L` | Lock screen (Caelestia) |
| `CTRL + ALT + H` | Clipboard history (`caelestia clipboard`) |
| `CTRL + SUPER + SHIFT + R` | Restart the Caelestia shell |
| `SUPER + E` | File manager (Nautilus) |
| `SUPER + B` | Browser (Chrome; Chromium on arm64) |
| `SUPER + Q` | Close window |
| `SUPER + F` | Fullscreen |
| `SUPER + V` | Toggle floating |
| `SUPER + S` | Toggle scratchpad |
| `SUPER + 1-0` | Switch workspace |
| `SUPER + SHIFT + 1-0` | Move window to workspace |
| `SUPER + Arrows / H J K` | Focus window |
| `SUPER + SHIFT + Arrows / H J K L` | Move window |
| `SUPER + ALT + Arrows / H J K L` | Resize window |
| `SUPER + mouse drag` | Move floating window |
| `SUPER + right-click drag` | Resize floating window |
| `Print` | Screenshot selection → clipboard |
| `SHIFT + Print` | Screenshot monitor → clipboard |
| `SUPER + SHIFT + S` | Move window to scratchpad |
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

### Update the WezTerm fork

WezTerm is built from the `floating-splits` branch of `jad617/wezterm`, pinned in `flake.lock`:

```bash
sudo nix flake update wezterm-src --flake /etc/nixos && sudo nixos-rebuild switch --impure --flake /etc/nixos#$(hostname)
```

### Preview changes before applying

```bash
sudo nixos-rebuild dry-activate --upgrade
```

### Roll back if something breaks

```bash
sudo nixos-rebuild switch --rollback
```

Or reboot and select the previous generation from the boot menu (Limine on UEFI, GRUB otherwise).

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
| Hyprland  | `nixos/config/hypr/hyprland.lua` (Lua: Hyprland 0.57+ no longer reads `hyprland.conf`) |
| Caelestia | `~/.config/caelestia/shell.json` (bar, launcher, lock, idle). Seeded once from `nixos/config/caelestia/shell.json` (opaque panels), then owned by Caelestia's settings UI |
| HyprMod   | `nixos/config/hypr/hyprland-gui.lua` (settings saved from the HyprMod app, loaded last by `hyprland.lua`) |
| Neovim    | `editors/nvim/` |
| WezTerm   | `terminal/wezterm/wezterm.lua` (the `jad617/wezterm` fork, `floating-splits` branch, built by Nix) |
| Zsh       | `shell/zsh/zshrc` + `my_aliases.sh` |
| NixOS     | `nixos/configuration.nix` + `nixos/hosts/*.nix` (copied to `/etc/nixos/`) |

After editing `configuration.nix`, apply with:

```bash
sudo nixos-rebuild switch
```

---

## Multi-Monitor Setup

Monitors are laid out by Hyprland itself, in `nixos/config/hypr/hyprland.lua`:

1. **Pinned desk layout**: screens matched by model (`desc:…`), so the order
   survives KVM switches and re-plugging no matter which screen connects first.
   Find the descriptions with:
   ```bash
   hyprctl monitors | grep description
   ```
2. **`monitors.conf`**: written by `nwg-displays` (GUI to arrange monitors)
   for anything not pinned.
3. **Fallback**: any other monitor gets its preferred mode, placed automatically.

Apply changes with `hyprctl reload`.

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
cat ~/.cache/nixos-rebuild.log    # written by init.sh
```

### Hyprland won't start

```bash
# Check the config (Hyprland 0.57+ only reads hyprland.lua)
Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

# Check logs
cat $XDG_RUNTIME_DIR/hypr/*/hyprland.log

# Try launching manually from TTY
Hyprland
```

### GPU drivers

`init.sh` detects the GPU (`nixos/lib/detect-gpu.sh` → `/etc/nixos/gpu.json`) and `nixos/gpu.nix`
configures it. Steam is installed on every x86_64 host.

| GPU | Driver |
|-----|--------|
| NVIDIA GTX 16xx / RTX 20xx and newer | current driver, open kernel module |
| NVIDIA GTX 9xx / 10xx (e.g. GTX 1070) | 580 series, proprietary (the last one that supports them) |
| AMD | Mesa (RADV, radeonsi), `amdgpu` in the initrd |

On NVIDIA, the session also gets Hyprland's two required variables, `LIBVA_DRIVER_NAME=nvidia` and
`__GLX_VENDOR_LIBRARY_NAME=nvidia`, plus `NVD_BACKEND=direct` for hardware video decoding.

### NVIDIA issues

```bash
# Confirm driver is loaded
nvidia-smi

# What init.sh detected, and the session variables
cat /etc/nixos/gpu.json
env | grep -E 'LIBVA|__GLX|NVD'
```

### Caelestia bar not showing

```bash
# Restart the shell (or CTRL + SUPER + SHIFT + R)
caelestia shell -k; caelestia shell -d

# Run it in the foreground to see errors
caelestia shell
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
