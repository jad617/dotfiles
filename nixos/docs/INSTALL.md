# Installing NixOS

`nixos/install-from-linux.sh` installs NixOS onto a disk, either from the running Pop!_OS (no live
USB needed) or from a live CD / USB. Each OS keeps its own disk and its own EFI partition, and you
pick one in the firmware boot menu.

```
nvme0n1  Pop!_OS  ── never offered ──  EFI: nvme0n1p1, entry "Pop!_OS"
sda      NixOS    sda2 EFI (NIXBOOT) + sda3 root (nixos)   entry "Limine"
         + kept data partition (sda1 = /backup)
```

The host must exist in `flake.nix` / `hosts/` (e.g. `hashirama`).

With **encryption** (`--encrypt`, or "Encrypt" in the menus), the NixOS partition is LUKS2
(label `nixos-crypt`) with Btrfs inside, subvolumes `@` `@home` `@nix` `@log`, zstd compression.
The passphrase is typed at every boot on the Plymouth splash, then the boot shows Caelestia's lock
screen. Plan and background: [ENCRYPTION.md](ENCRYPTION.md).

---

## Guided install (arrow-key menus)

```bash
nixos/install-from-linux.sh
```

| Screen | What you pick |
|---|---|
| Host | the flake host (skipped when this machine's hostname is one) |
| Disk | every disk with its size, model and contents: `[empty]`, `[data: ext4, mounted on /backup]`, `[ANOTHER OS: ...]`. Every disk is listed; the running system's disk (and the live USB) shows `[IN USE ..., can't be used]` and can't be picked |
| Layout | what this disk allows (see below) |
| Encryption | right after the layout, for any layout: LUKS2 + Btrfs (passphrase at every boot) or plain ext4. **No** is pre-selected. Then the disk passphrase, twice |
| Size | the NixOS partition size, or how much the shrunk partition keeps |
| User, timezone, password | the user is always asked (pre-filled with your login name when run from an installed Linux; empty on a live CD); the timezone only on a live CD (otherwise: this system's) |
| Wi-Fi | the Wi-Fi networks saved on this system (Pop, or the live session), all ticked: `Space` ticks, `a` all / none. Copied with their passwords so NixOS is online at its first boot |
| SSH keys | optional: the key pairs, `config` and `known_hosts` from your `~/.ssh` (fingerprint and comment shown, passphrase-protected keys marked), all ticked; untick what NixOS should not have |
| Summary | in sections (NixOS, Disk, Copied to NixOS, Other disks), colored by what happens: **red** destroyed (erased, deleted, formatted), **yellow** changed with data kept (shrunk, converted, unmounted), **green** created or kept, **blue** copied. **Cancel** is pre-selected |
| Confirm | a last yes / no that names what changes on the disk (`Deleting: sda2, sda3`, `Erasing: all of sda`, `Formatting: ...`, `Shrinking: ...`); **Yes** is pre-selected, No (or `←`) goes back to the Summary. In the numbered mode (and piped input) the name is typed instead: `erase <disk>`, `delete sda2 sda3`, or the disk / partition name |

Keys: `↑`/`↓` (or `k`/`j`, or a number) to move, `→` or `Enter` to pick, **`←` to go back one
screen**, `Space` to tick, `q` or `Esc` to quit. On text fields (sizes, user, passwords) the arrows also
move between screens; `Backspace` edits, `Ctrl-U` clears. Screens with nothing to ask (the host when
the hostname matches one, the size for an erase...) are passed over both ways. `←` on the first
screen asks whether to quit. The **Summary** is the last screen you can go back from; after the
confirmation the install runs to the end without questions.

The screens are cards like init.sh's (Catppuccin Macchiato in 24-bit terminals, basic colors on a
text console), with what you picked so far in the header. **Nothing is written to any disk before
the final confirmation.** Without a terminal (piped input) you get numbered prompts instead, where
`<` goes back (`NIXOS_INSTALL_TEXT=1` forces them).

### Layouts

| Layout | Offered when | What happens |
|---|---|---|
In this order (the first one is selected):

| Layout | Offered when | What happens |
|---|---|---|
| **Delete some, keep the others** | the disk has partitions (also with another OS on it) | you tick the partitions to delete (all unticked at first); the others are kept untouched; NixOS (1 GiB EFI + NixOS, all or a size you pick) goes in the largest free space left |
| **Use the free space** | the disk has ≥ 21 GiB unpartitioned | 1 GiB EFI + NixOS (all or a size you pick) in the largest free space; all partitions kept |
| **Shrink a partition** | an ext4 partition can free ≥ 21 GiB | the partition keeps N GiB (data and UUIDs kept), NixOS goes into the freed space |
| **Erase the whole disk** (in yellow) | always | new GPT: 1 GiB EFI + NixOS on the rest |

Partitions mounted right now are shown in **yellow** in the disk's listing. Formatting two existing
partitions as they are (no new ones) is only in the command-line options: `--boot-part` / `--root-part`.
The Encryption question that follows has **Encrypt** first and pre-selected.

On a disk holding another OS, NixOS only goes **in its place**: **Erase**, or **Delete** with every
partition of that OS ticked (its boot partition, LUKS / LVM / Windows / ZFS partitions); keeping one
of them is refused. NixOS is never squeezed in next to another OS. Deleted partitions must free
21 GiB **in one piece** (next to each other, or next to free space): the checklist says so when
they don't, and keeps your ticks. Mounted partitions (in use by the running system) are shown
in **red**: ticking one opens a red popup ("Delete it anyway?", **No** pre-selected); if you say
yes, it is unmounted before it is deleted.
An MBR disk is converted to GPT in place for "free space", "shrink" and "delete" (partitions kept;
the script checks that no partition moved). A partition table backup is saved to
`~/<disk>-partition-table-<date>.sfdisk` before any change to an existing table.

### Clean install over an existing system

Pick the disk marked `[ANOTHER OS: ...]` and **Erase**. A red **WARNING: data loss** screen lists
every partition that will be destroyed (size, filesystem, label, what is mounted, how much is used,
which firmware boot entry points to it), says that system will no longer boot, and pre-selects
**Cancel**. The last screen then says `Erasing: all of <disk> (...)` and asks yes / no. After the install, the erased system's firmware boot
entries are removed.

To keep a data partition of that disk, pick **Delete** instead: tick the old system's partitions,
leave the data one unticked. The warning lists what is deleted and what is kept, and the last
screen says `Deleting: sda2, sda3` and asks yes / no.

The disk the running system boots from is listed but can't be picked, not even for an erase: to replace Pop!_OS
itself, boot a live CD (see below) and erase `nvme0n1` from there.

### Mounted partitions

Partitions that a layout changes are unmounted first and, for **Shrink**, mounted again afterwards.
If one is busy (a shell `cd`'ed into it, a file manager, Claude Code started from it), the script
lists the programs with `fuser` and stops, before anything was changed:

```bash
sudo fuser -vm /backup        # should list only "kernel mount"
```

### SSH keys

`lib/copy-ssh.sh` copies the items you tick from `~/.ssh` into the new home, with the permissions `ssh`
requires (folder `700`, private keys and `known_hosts` `600`, `.pub` `644`), owned by your NixOS
user. Each key pair is one item (the private key and its `.pub`). Private keys are copied as they
are: a passphrase stays. Not copied: `*.old` backups, sockets, folders. Without the menus nothing is
copied unless you pass `--ssh`. On a live CD this is the live session's `~/.ssh` (usually empty).

### Wi-Fi

Each network is rebuilt from its essentials (name, SSID, security, password) by `lib/export-wifi.sh`,
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
nixos/install-from-linux.sh --host hashirama --delete /dev/sda2,/dev/sda3 [--size 300]  # keep the rest
nixos/install-from-linux.sh --host hashirama --boot-part /dev/sda2 --root-part /dev/sda3
nixos/install-from-linux.sh --host hashirama --boot-part /dev/sda2 --root-part /dev/sda3 --encrypt
```

| Option / variable | Effect |
|---|---|
| `--size N` | NixOS partition size in GiB (free space / shrink / delete; default: all of it) |
| `--delete P1,P2` | delete these partitions (all on one disk), keep the others, NixOS in the space freed |
| `--keep N` | GiB the shrunk partition keeps (at least its data + 10 % + 1 GiB) |
| `--host`, `--user`, `--timezone` | as in the menus (`--host` and `--user` are required on a live CD) |
| `--wifi W` | Wi-Fi networks to copy: `active` (default: the one connected now), `all`, `none`, or names separated by commas |
| `--ssh S` | SSH items from `~/.ssh` to copy: `none` (default), `all`, or names separated by commas, e.g. `id_rsa,known_hosts` |
| `--encrypt` | NixOS partition as LUKS2 + Btrfs (any layout); asks for the disk passphrase twice |
| `--continue` | continue an existing install, nothing formatted (see "Continue an existing install") |
| `--status` | the progress of the install running in the background (or the result of the last one) |
| `NIXOS_INSTALL_FOREGROUND=1` | run the install in the terminal instead of in the background |
| `NIXOS_PASSWORD=...` | password for the NixOS user, instead of the prompt |
| `NIXOS_LUKS_PASSPHRASE=...` | disk passphrase (with `--encrypt`), instead of the prompt |
| `NIXOS_INSTALL_YES=1` | skip the warning question and the final confirmation |
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

- **The host and user are not guessed**: the ISO's hostname (`nixos`) and user (`nixos`) are not
  yours. The menus ask; without them pass `--host` and
  `--user`. The timezone defaults to America/Toronto.
- **Root shells are fine**: `sudo` is only used when not root.
- **Pop!_OS is still recognised** although nothing of it is mounted: a disk counts as "another OS"
  when a firmware boot entry points to one of its partitions ("Pop!_OS" → `nvme0n1p1`), or when it
  holds LUKS, LVM, NTFS / BitLocker or ZFS partitions. NixOS's own `NIXBOOT` partition does not
  count, so re-installing works. The live USB itself is listed but can't be picked.
- **Builds use the target disk**, not RAM: the system goes straight into its store, and build temp
  files go to `/mnt/nixos-install/tmp`.

---

## Continue an existing install

To redo an install without reinstalling: after a failed or interrupted build, after changing the
config, or to set up the home again. Pick the disk: when it holds a NixOS install (a `NIXBOOT` EFI
partition and a `nixos` or `nixos-crypt` one), an **Existing NixOS** screen offers:

- **Continue this install** (default): **nothing is formatted**, the partitions are only mounted (an
  encrypted one is unlocked with its passphrase, typed once and checked). `/etc/nixos` is written
  again from this checkout, the system is built (what is already built or downloaded is reused, so
  a failed build goes on where it stopped) and the home is set up again (dotfiles, home setup,
  Wi-Fi, SSH keys, boot entries).
- **New install on this disk**: the usual layouts.

The password can be left empty (Enter on the first field): the current one is kept. The checkout
already on NixOS (`~/nodestack/dotfiles`) is moved to `dotfiles.bak-<date>`, never deleted, before
this one is copied there. Without the menus:

```bash
nixos/install-from-linux.sh --host hashirama --continue                # found by the labels (one install)
nixos/install-from-linux.sh --host hashirama --continue --boot-part /dev/sda2 --root-part /dev/sda3
```

## The install runs in the background

After the last yes / no, the install itself (the 7 steps below) runs as a background service
(`systemd-run`, unit `nixos-install`, as root), not in your terminal: **you can close the terminal,
the tab, or the terminal app, and work on something else**. Nothing asks a question after the
confirmation, so nothing waits for you.

- The terminal then shows the progress: the step (`Step 6/7 nixos-install`), the time so far and in
  this step, and during the build two bars, `Builds 34 / 120` and `Downloads 812 / 1450`, counted from
  Nix's output, with the last lines of the log. `q` leaves the view (the install goes on).
- Back to it, from any terminal: `bash nixos/install-from-linux.sh --status` (running the installer
  while an install runs also shows it). It ends with the final box (reboot steps) or the error.
- Everything is logged to `~/nixos-install-<date>.log` (also `journalctl -u nixos-install`).
- The answers, passwords included, reach the service through `/run/nixos-install/plan.env` (RAM,
  root only, mode 600), deleted as soon as it is read: never on a command line or in the
  service's environment, never in the log.
- Scripts and piped input (no terminal) keep the install in the foreground; so does
  `NIXOS_INSTALL_FOREGROUND=1`. One install at a time.

## What the script does, in order

1. **Nix**: installed if missing (`/nix` + `nix-daemon`), the only change to the running system.
2. **Tools**: `nixos-install`, parted, gptfdisk, e2fsprogs, dosfstools, efibootmgr (+ cryptsetup
   and btrfs-progs with `--encrypt`), from the nixpkgs revision pinned in `flake.lock`.
3. **Disk**: unmount what the layout changes, then erase / convert MBR → GPT / shrink / add the two
   partitions.
4. **Format**: EFI as FAT32 `NIXBOOT`, NixOS as ext4 `nixos`, mounted on `/mnt/nixos-install`.
   With `--encrypt`: LUKS2 `nixos-crypt` opened as `cryptroot`, Btrfs `nixos` inside, subvolumes
   `@` `@home` `@nix` `@log` mounted with `compress=zstd,noatime`. The passphrase only goes
   through stdin.
5. **Config**: `/etc/nixos` from this checkout (`lib/write-config.sh`: flake, `configuration.nix`, hosts,
   GPU detection). The running system's swap is removed from `hardware-configuration.nix`, so NixOS
   does not wait for Pop's encrypted swap at boot. With `--encrypt`, the generated
   `boot.initrd.luks.devices."cryptroot"` entry is checked (it stops otherwise: NixOS couldn't
   unlock its disk) and `compress=zstd` / `noatime` are added to the Btrfs mounts; the monthly
   Btrfs scrub turns itself on (`configuration.nix`).
6. **nixos-install**: Limine (themed boot menu) on the new EFI partition. **The first build is long**: some
   packages (Terraform, Vault, Steam, Chrome, Rust crates) are built from source.
7. **User**: password; this checkout copied to `~/nodestack/dotfiles` on NixOS and its configs linked
   (`lib/link-dotfiles.sh`: zsh, Neovim, WezTerm, tmux, Hyprland, GTK, wallpapers, Caelestia's
   `shell.json`); the home's one-time setup (`lib/home-setup.sh`: `~/.disable_copilot`, the tmux
   plugin manager, Terraform's zsh completion); the chosen Wi-Fi networks copied (`lib/export-wifi.sh`) and the chosen SSH keys
   (`lib/copy-ssh.sh`); stale firmware entries removed: those of an erased OS, and those that point at
   the NixOS EFI partition at a file that's gone (e.g. the old boot loader's, after a reinstall).
   Entries that point at no disk at all are listed at the end, not removed.

So a fresh install is complete: the first login has your Hyprland config (it starts Caelestia), the
dark theme (set system-wide in `configuration.nix`), zsh, and is online. Nothing has to be run after it.

It refuses to start while something is mounted on `/mnt/nixos-install` (another install running).

---

## Safety checks

Never offered, and refused when passed as arguments:

- the disk the running system needs: what `/` and active swap sit on, and the live medium;
- a disk holding another OS, except for an erase (behind the warning, or
  `NIXOS_INSTALL_ALLOW_OS_DISK`) or a delete that removes every partition of that OS. LUKS, LVM, Windows and ZFS partitions count as another OS,
  except NixOS's own LUKS partition (label `nixos-crypt`), so an encrypted NixOS can be reinstalled;
- for `--boot-part` / `--root-part`: mounted partitions, partitions on different disks, a non-GPT disk,
  or a boot partition that is not an EFI System partition (type EF00).

Shrinking runs `e2fsck` first and stops on any error it cannot fix; it recomputes the minimum size
after the check, shrinks the filesystem below the target, resizes the partition (same start sector),
grows the filesystem back to fill it and checks it again.

---

## After the install

1. **Boot entries.** NixOS adds "Limine" and puts it first. Pop's entry stays. The
   final box shows the exact command to put the other OS first again, e.g.:

   ```bash
   efibootmgr                          # Boot0004* Pop!_OS, Boot0007* Limine
   sudo efibootmgr -o 0004,0005,...    # Pop first again (keep the other numbers)
   ```

   Either way, the firmware boot menu (F8 / F11 / F12 at power-on) lets you pick an OS each time.
2. **Reboot into NixOS** and log in: everything is set up. Later, `bash ~/nodestack/dotfiles/nixos/init.sh`
   applies updates after a `git pull` (re-links the configs, rebuilds; a failed rebuild, e.g. offline,
   is reported at the end with its log in `~/.cache/nixos-rebuild.log`), and once you ran
   `gh auth login`, it adds the `gh copilot` extension (the one thing that needs your GitHub login).
3. Change a temporary password: `passwd`.

---

## Shared folders (hashirama)

`~/Pictures`, `~/Downloads`, `~/Documents` and `~/Desktop` are links to `/backup/shared/<name>` on
both systems, so there is one copy, seen from Pop!_OS and NixOS. On NixOS the links come from
`hosts/hashirama.nix` (`system.activationScripts.sharedFolders`), recreated at every boot and rebuild,
so a reinstall gets them back. A real folder in the way is renamed `<name>.local-<date>`, never
deleted (one with no files at all, as a fresh install leaves it, is just cleared). Steam games can
share a library folder there too (`/backup/shared/SteamLibrary`); Chrome profiles cannot (their
passwords are encrypted per system): use Chrome sync.

---

## Removing NixOS

NixOS lives only on its two partitions, so removing it does not affect Pop!_OS:

```bash
efibootmgr                           # find "Limine" (and "UEFI OS" on NixOS's EFI partition)
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
| `NAR hash mismatch` | re-run; `lib/write-config.sh` locks the flake before installing |
| Build fails halfway | the view shows the step and the last log lines (full log: `~/nixos-install-<date>.log`); fix the cause, then pick the disk and "Continue this install" (or `--continue`): nothing is formatted, what was built is reused |
| `could not start the background install` | no systemd here (or `systemd-run` refused): run with `NIXOS_INSTALL_FOREGROUND=1` |
| `Failed to install bootloader` / `/boot is not a mounted partition` | `/boot` was unmounted during the install: mount both partitions back on `/mnt/nixos-install` and re-run the same `nixos-install` (it reuses the build) |
| NixOS not in the boot menu | firmware boot menu → pick the disk itself; or `efibootmgr -v` from Pop |
| NixOS boots, `/backup` missing | `nofail` let it boot: check the UUID in `hosts/<host>.nix` |
| Wi-Fi: right password, still refused | `journalctl -u wpa_supplicant`: `AUTH-REJECT ... status_code=33` is the router refusing that band. Remove the BSSID lock: `nmcli con modify <name> 802-11-wireless.bssid ""` (or `802-11-wireless.band a` for 5 GHz only) |
| Bare Hyprland, no Caelestia bar | the configs are not linked (`~/.config/hypr` is Hyprland's generated folder): `bash ~/nodestack/dotfiles/nixos/lib/link-dotfiles.sh`, log out and in |
