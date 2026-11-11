# Installing NixOS

`nixos/install-from-linux.sh` installs NixOS onto a disk, either from the running Pop!_OS (no live
USB needed) or from a live CD / USB. Each OS keeps its own disk and its own EFI partition, and you
pick one in the firmware boot menu.

```
nvme0n1  Pop!_OS  ── never offered ──  EFI: nvme0n1p1, entry "Pop!_OS"
sda      NixOS    sda2 EFI (NIXBOOT) + sda3 root (nixos)   entry "Linux Boot Manager"
         + kept data partition (sda1 = /backup)
```

The host must exist in `flake.nix` / `hosts/` (e.g. `hashirama`).

---

## Guided install (arrow-key menus)

```bash
nixos/install-from-linux.sh
```

| Screen | What you pick |
|---|---|
| Host | the flake host (skipped when this machine's hostname is one) |
| Disk | every disk with its size, model and contents: `[empty]`, `[data: ext4, mounted on /backup]`, `[ANOTHER OS: ...]`. The running system's disk is never listed |
| Layout | what this disk allows (see below) |
| Size | the NixOS partition size, or how much the shrunk partition keeps |
| User, timezone, password | user and timezone only on a live CD (otherwise: you, this system's timezone) |
| Wi-Fi | the Wi-Fi networks saved on this system (Pop, or the live session), all ticked: `Space` ticks, `a` all / none. Copied with their passwords so NixOS is online at its first boot |
| Summary | everything that will be formatted, shrunk, kept, unmounted, left untouched. **Cancel** is pre-selected |
| Confirm | type the disk or partition name (`erase <disk>` for a disk with data) |

Keys: `↑`/`↓` (or `k`/`j`, or a number) to move, `Enter` to pick, `Space` to tick, `q` to quit. Every screen shows
what you picked so far in its title bar. **Nothing is written to any disk before the typed
confirmation.** Without a terminal (piped input) you get numbered prompts instead
(`NIXOS_INSTALL_TEXT=1` forces them).

### Layouts

| Layout | Offered when | What happens |
|---|---|---|
| **Erase the whole disk** | always | new GPT: 1 GiB EFI + NixOS on the rest |
| **Use the free space** | the disk has ≥ 21 GiB unpartitioned | 1 GiB EFI + NixOS (all or a size you pick) in the largest free space; all partitions kept |
| **Shrink a partition** | an ext4 partition can free ≥ 21 GiB | the partition keeps N GiB (data and UUIDs kept), NixOS goes into the freed space |
| **Two existing partitions** | GPT disk with an EFI partition | you pick an EFI partition and one for NixOS; both are formatted |

Only **Erase** is offered on a disk holding another OS: NixOS is never squeezed in next to it.
An MBR disk is converted to GPT in place for "free space" and "shrink" (partitions kept; the
script checks that no partition moved). A partition table backup is saved to
`~/<disk>-partition-table-<date>.sfdisk` before any change to an existing table.

### Clean install over an existing system

Pick the disk marked `[ANOTHER OS: ...]` and **Erase**. A red **WARNING: data loss** screen lists
every partition that will be destroyed (size, filesystem, label, what is mounted, how much is used,
which firmware boot entry points to it), says that system will no longer boot, and pre-selects
**Cancel**. Then you type `erase <disk>`. After the install, the erased system's firmware boot
entries are removed.

The disk the running system boots from is never offered, not even for an erase: to replace Pop!_OS
itself, boot a live CD (see below) and erase `nvme0n1` from there.

### Mounted partitions

Partitions that a layout changes are unmounted first and, for **Shrink**, mounted again afterwards.
If one is busy (a shell `cd`'ed into it, a file manager, Claude Code started from it), the script
lists the programs with `fuser` and stops, before anything was changed:

```bash
sudo fuser -vm /backup        # should list only "kernel mount"
```

### Wi-Fi

Each network is rebuilt from its essentials (name, SSID, security, password) by `export-wifi.sh`,
never copied as is: **no access-point (BSSID) lock**, no MAC or interface name of this machine. A
profile locked to one access point is what broke the first NixOS boot on hashirama: the router
(band steering) rejects that card on 2.4 GHz (`AUTH-REJECT ... status_code=33` in the journal), and
the profile NixOS's network menu created was locked to the 2.4 GHz access point. Unlocked, the card
moves to 5 GHz like on Pop. Copied: open, WPA/WPA2-Personal and WPA3-Personal networks; skipped:
enterprise (802.1X) and WEP. Passwords go from this system's NetworkManager straight into the new
system (`/etc/NetworkManager/system-connections`, mode 600), never into the repo.

On a live system without NetworkManager (the minimal NixOS ISO uses `wpa_supplicant`) there is
nothing to copy: connect on NixOS with `nmtui`, or plug in a cable.

---

## Without the menus (scripts, or to repeat an install)

```bash
nixos/install-from-linux.sh --host hashirama /dev/nvme1n1                      # erase
nixos/install-from-linux.sh --host hashirama --free-space /dev/sda [--size 400]
nixos/install-from-linux.sh --host hashirama --shrink /dev/sda1 --keep 530 [--size 400]
nixos/install-from-linux.sh --host hashirama --boot-part /dev/sda2 --root-part /dev/sda3
```

| Option / variable | Effect |
|---|---|
| `--size N` | NixOS partition size in GiB (free space / shrink; default: all of it) |
| `--keep N` | GiB the shrunk partition keeps (at least its data + 10 % + 1 GiB) |
| `--host`, `--user`, `--timezone` | as in the menus (`--host` and `--user` are required on a live CD) |
| `--wifi W` | Wi-Fi networks to copy: `active` (default: the one connected now), `all`, `none`, or names separated by commas |
| `NIXOS_PASSWORD=...` | password for the NixOS user, instead of the prompt |
| `NIXOS_INSTALL_YES=1` | skip the typed confirmation |
| `NIXOS_INSTALL_ALLOW_OS_DISK=/dev/X` | let the erase mode wipe X although it holds another OS |

Safer than `NIXOS_INSTALL_YES`: pipe the expected name into the prompt, so a wrong target still fails:

```bash
echo sda3 | NIXOS_PASSWORD=changeme nixos/install-from-linux.sh --host hashirama --boot-part /dev/sda2 --root-part /dev/sda3
```

---

## From a live CD / USB

The same script works from the NixOS ISO or another live system (e.g. Ubuntu), for when Pop!_OS
does not boot, or to replace it:

```bash
# NixOS ISO: git and nix are there; on Ubuntu, Nix is installed into the live session (RAM)
nix-shell -p git --command "git clone https://github.com/jad617/dotfiles ~/dotfiles"
~/dotfiles/nixos/install-from-linux.sh
```

What changes on a live system (detected from `/etc/os-release` or a RAM root filesystem):

- **The host and user are not guessed**: the ISO's hostname `nixos` is also the VM host in
  `flake.nix`, and its user `nixos` is not yours. The menus ask; without them pass `--host` and
  `--user`. The timezone defaults to America/Toronto.
- **Root shells are fine**: `sudo` is only used when not root.
- **Pop!_OS is still recognised** although nothing of it is mounted: a disk counts as "another OS"
  when a firmware boot entry points to one of its partitions ("Pop!_OS" → `nvme0n1p1`), or when it
  holds LUKS, LVM, NTFS / BitLocker or ZFS partitions. NixOS's own `NIXBOOT` partition does not
  count, so re-installing works. The live USB itself is never offered.
- **Builds use the target disk**, not RAM: the system goes straight into its store, and build temp
  files go to `/mnt/nixos-install/tmp`.

---

## What the script does, in order

1. **Nix**: installed if missing (`/nix` + `nix-daemon`), the only change to the running system.
2. **Tools**: `nixos-install`, parted, gptfdisk, e2fsprogs, dosfstools, efibootmgr, from the nixpkgs
   revision pinned in `flake.lock`.
3. **Disk**: unmount what the layout changes, then erase / convert MBR → GPT / shrink / add the two
   partitions.
4. **Format**: EFI as FAT32 `NIXBOOT`, NixOS as ext4 `nixos`, mounted on `/mnt/nixos-install`.
5. **Config**: `/etc/nixos` from this checkout (`write-config.sh`: flake, `configuration.nix`, hosts,
   GPU detection). The running system's swap is removed from `hardware-configuration.nix`, so NixOS
   does not wait for Pop's encrypted swap at boot.
6. **nixos-install**: systemd-boot on the new EFI partition. **The first build is long**: some
   packages (Terraform, Vault, Steam, Chrome, Rust crates) are built from source.
7. **User**: password; this checkout copied to `~/nodestack/dotfiles` on NixOS and its configs linked
   (`link-dotfiles.sh`: zsh, Neovim, WezTerm, tmux, Hyprland, kanshi, GTK, wallpapers, Caelestia's
   `shell.json`); the chosen Wi-Fi networks copied (`export-wifi.sh`); stale firmware entries of an
   erased OS removed.

So the first login already has your Hyprland config, which starts Caelestia, and is online, before
`init.sh` ever runs.

It refuses to start while something is mounted on `/mnt/nixos-install` (another install running).

---

## Safety checks

Never offered, and refused when passed as arguments:

- the disk the running system needs: what `/` and active swap sit on, and the live medium;
- a disk holding another OS, except for an erase (behind the warning, or
  `NIXOS_INSTALL_ALLOW_OS_DISK`);
- for "two existing partitions": mounted partitions, partitions on different disks, a non-GPT disk,
  or a boot partition that is not an EFI System partition (type EF00).

Shrinking runs `e2fsck` first and stops on any error it cannot fix; it recomputes the minimum size
after the check, shrinks the filesystem below the target, resizes the partition (same start sector),
grows the filesystem back to fill it and checks it again.

---

## After the install

1. **Boot entries.** NixOS adds "Linux Boot Manager" and puts it first. Pop's entry stays. The
   final box shows the exact command to put the other OS first again, e.g.:

   ```bash
   efibootmgr                          # Boot0004* Pop!_OS, Boot0005* Linux Boot Manager
   sudo efibootmgr -o 0004,0005,...    # Pop first again (keep the other numbers)
   ```

   Either way, the firmware boot menu (F8 / F11 / F12 at power-on) lets you pick an OS each time.
2. **Reboot into NixOS**, log in and run `bash ~/nodestack/dotfiles/nixos/init.sh` for the rest
   (rebuild from the checkout, default shell, tmux plugins, theme). It links the configs first and
   keeps going if the rebuild fails (e.g. offline): the failure is reported at the end, with its log
   in `~/.cache/nixos-rebuild.log`. Run it again once online.
3. Change a temporary password: `passwd`.

---

## Removing NixOS

NixOS lives only on its two partitions, so removing it does not affect Pop!_OS:

```bash
efibootmgr                           # find "Linux Boot Manager" (and its "Fallback")
sudo efibootmgr -b 0005 -B           # delete each entry
sudo wipefs -a /dev/sda2 /dev/sda3   # or delete the partitions and grow the data one
```

---

## Troubleshooting

| Problem | What to do |
|---|---|
| `... is busy` while unmounting | `sudo fuser -vm <mountpoint>`, close what it lists, re-run |
| `/mnt/nixos-install is in use` | another install is running; or a failed one left it: `sudo umount -R /mnt/nixos-install` |
| `the kernel does not show ... yet` | the table was written but the kernel kept the old one: reboot, re-run with `--boot-part` / `--root-part` |
| `e2fsck failed` | nothing was resized: check the filesystem by hand first |
| `NAR hash mismatch` | re-run; `write-config.sh` locks the flake before installing |
| Build fails halfway | re-run with `--boot-part` / `--root-part` on the two NixOS partitions |
| `Failed to install bootloader` / `/boot is not a mounted partition` | `/boot` was unmounted during the install: mount both partitions back on `/mnt/nixos-install` and re-run the same `nixos-install` (it reuses the build) |
| NixOS not in the boot menu | firmware boot menu → pick the disk itself; or `efibootmgr -v` from Pop |
| NixOS boots, `/backup` missing | `nofail` let it boot: check the UUID in `hosts/<host>.nix` |
| Wi-Fi: right password, still refused | `journalctl -u wpa_supplicant`: `AUTH-REJECT ... status_code=33` is the router refusing that band. Remove the BSSID lock: `nmcli con modify <name> 802-11-wireless.bssid ""` (or `802-11-wireless.band a` for 5 GHz only) |
| Bare Hyprland, no Caelestia bar | the configs are not linked (`~/.config/hypr` is Hyprland's generated folder): `bash ~/nodestack/dotfiles/nixos/link-dotfiles.sh`, log out and in |
