# Disk encryption & layout plan

Status: **phase 1 ready to run** (installer support done and tested on a loop device); phase 2 and Secure Boot + TPM planned. Holds the decisions and the steps so the work
can continue from another OS (phase 1 runs from Pop!_OS).

- **Phase 1** (next): reinstall NixOS on the SATA disk as **LUKS2 + Btrfs**.
  The LUKS passphrase is typed at boot on the Plymouth splash; Secure Boot
  stays **off**. Pop!_OS stays on the NVMe, unchanged.
- **Phase 2** (later, when Pop!_OS is removed): wipe the NVMe, move the boot
  partition and NixOS onto it with Btrfs (online, no reinstall), and leave the
  SATA disk only for the shared/backup data.
- **On hold:** Secure Boot + TPM auto-unlock. Kept below as
  notes ("On hold") for whenever it's picked up again.

Disk roles, by phase (device names are examples; check with `lsblk -f`):

| | Phase 1 | Phase 2 |
|---|---|---|
| SATA disk | EFI (NixOS) · LUKS+Btrfs (NixOS) · shared/backup data | shared/backup data only (old EFI + NixOS partitions reused) |
| NVMe disk | Pop!_OS (its own EFI, LUKS, swap) | EFI (NixOS) · LUKS+Btrfs (NixOS) |

---

## Decisions and why

- **LUKS2** encrypts the NixOS partition. Without the key, the data is
  unreadable: a live USB, a recovery/safe-mode trick, or moving the drive to
  another PC only reaches encrypted data.
- **Btrfs** on top (not ext4, not ZFS):
  - in the kernel (no out-of-tree module to break on `linuxPackages_latest`,
    unlike ZFS; the NVIDIA driver is already one out-of-tree module)
  - **online disk migration** (`btrfs device add` / `remove`): what phase 2 relies on
  - snapshots and zstd compression; subvolumes instead of fixed partition sizes
  - single-disk Btrfs is mature (Fedora's default since 2020). Avoid RAID5/6
    (not used here). Keep 10–15 % free; old full-disk ENOSPC issues are largely
    gone on 6.x/7.x kernels (dynamic block-group reclaim).
- **Passphrase at boot, then the Caelestia lock (two passwords per boot).**
  The LUKS passphrase is typed on the Catppuccin Plymouth splash (a graphical
  prompt, not a text console; the systemd initrd hands the request to
  Plymouth). The boot then ends on the Caelestia lock screen, exactly as
  today (greetd auto-login with `CAELESTIA_AUTOLOCK=1`): no login change is
  needed for encryption. Caelestia also locks on idle (15 min) and on demand.
- **Secure Boot off, no TPM (for now).** A passphrase that only lives in your
  head needs neither. The one gap left is an "evil maid" (someone tampering
  with the unencrypted boot files to capture the passphrase), a targeted
  attack; Secure Boot would close it later.
- **Fresh install** rather than in-place encryption (`cryptsetup reencrypt`):
  the system rebuilds from this repo, and an interrupted in-place conversion can
  destroy the partition.

### Pop!_OS and Secure Boot (only matters once Secure Boot is turned on)

Pop!_OS boots with an **unsigned** systemd-boot, and `kernelstub` copies a new
kernel (`vmlinuz.efi`) and initrd into Pop's EFI partition on every kernel
update. With Secure Boot on, the firmware refuses to start it. Options:

1. **Sign Pop's boot files with the same keys (recommended while Pop stays).**
   Copy the Secure Boot keys (from NixOS's `/var/lib/sbctl`) to Pop!_OS (its
   disk is encrypted too), install `sbctl` there, sign Pop's
   `EFI/systemd/systemd-bootx64.efi`, `EFI/BOOT/BOOTX64.EFI` and the kernels
   under `EFI/Pop_OS-*/` and `EFI/Recovery-*/`, and add a kernel post-install
   hook on Pop (`/etc/kernel/postinst.d/zz-sbctl`) that re-signs after
   `kernelstub` runs. Check with `sbctl verify` on both systems.
2. **Turn Secure Boot off in the firmware to boot Pop, back on for NixOS.**
   No setup, but a firmware trip each time. Forgetting to turn it back on is
   harmless: NixOS's signed files boot either way, the TPM just doesn't
   release the key (PCR 7 differs), so the splash asks for the passphrase.
3. **Wait until Pop!_OS is gone** (phase 2) and turn Secure Boot on then.

---

## Phase 1: reinstall NixOS on the SATA disk

### What booting looks like after phase 1

1. **Boot menu** (2 s, Limine, Catppuccin-themed): the last 3 NixOS
   generations plus a **Pop!_OS** entry, which hands off to Pop's own boot
   loader on the NVMe (`boot.loader.limine.extraEntries` in the host file, by
   the partition GUID of Pop's EFI partition). Secure Boot stays off, so
   nothing about Pop's boot changes; the firmware's boot menu still works too.
   The reinstall keeps this: it's all in the repo's config.
2. **Plymouth splash** (Catppuccin Macchiato) with a **graphical password
   field** for the LUKS passphrase (dots as you type). The systemd initrd
   hands the passphrase request to Plymouth; no extra config needed.
   - It relies on the NVIDIA settings in `gpu.nix` (driver in the initrd,
     `nvidia_drm.fbdev=1`, simpledrm off) so the splash and prompt are at full
     resolution and don't drop out when the GPU driver takes over.
   - If Plymouth fails to start, the same prompt shows as plain console text
     and still works.
   - The initrd uses the US keyboard layout unless `console.keyMap` is set:
     keep that in mind for special characters in the passphrase.
3. **Caelestia lock screen** after the passphrase, as today: greetd
   auto-logs in, Hyprland starts locked (`CAELESTIA_AUTOLOCK=1` and
   `config/hypr/autolock.sh`), and the desktop opens after your user
   password. The config stays as it is.
4. **Idle**: Caelestia locks after **15 minutes** (only lock: no screens-off,
   no suspend; sleep is blocked system-wide in the host file).
   `config/caelestia/shell.json` → `general.idle.timeouts`.

### 1. Installer support (done)

`install-from-linux.sh --encrypt` (or "Encrypt" in the guided menus) does it all;
see INSTALL.md for the options. In order:

1. Asks for the disk passphrase twice (or takes `NIXOS_LUKS_PASSPHRASE`); refuses
   characters that can't be typed at the boot prompt.
2. Formats the EFI partition (FAT32 `NIXBOOT`), then the NixOS partition as LUKS2
   (label `nixos-crypt`; the passphrase only goes through stdin), opens it as
   `cryptroot`, creates Btrfs `nixos` with subvolumes `@` `@home` `@nix` `@log`,
   and mounts them with `compress=zstd,noatime`.
3. After `nixos-generate-config`: checks that `boot.initrd.luks.devices."cryptroot"`
   was generated (it stops before installing otherwise) and adds
   `compress=zstd` / `noatime` to the Btrfs mounts in `hardware-configuration.nix`.
4. After the install: removes firmware entries that point at the NixOS EFI
   partition at a file that's gone (the old systemd-boot entries, after this
   reinstall), and lists entries that point at no disk at all (old ubuntu /
   endeavouros-style leftovers) with the command to remove them.
5. Closes the LUKS mapping on exit, also after an error.

Its safety checks treat LUKS partitions as another OS's data, except its own
(`nixos-crypt`), so an encrypted NixOS can be reinstalled later. Pop!_OS's
LUKS disk is listed but can't be picked
(it's the running system's disk when the installer runs from Pop!_OS).

Tested on a loop device (format path with and without `--encrypt`; the
generated hardware config: LUKS entry by UUID, 4 Btrfs mounts with
compression; the full NixOS config evaluates with it).

### 2. NixOS config (done)

`configuration.nix` turns the monthly Btrfs scrub on by itself when `/` is
Btrfs (`services.btrfs.autoScrub`). Scrub = monthly read of everything against
Btrfs's checksums: repairs metadata (stored twice on one disk) and reports any
damaged file by name. The login stays as it is (Caelestia lock at boot).

Optional, later, for snapshots: snapper or btrbk with retention limits
(snapshots keep deleted data alive: prune them, or space doesn't come back),
and a `@snapshots` subvolume.

### 3. Before the reinstall (checklist)

1. Everything NixOS-side committed and pushed (this repo).
2. Copy what lives only on the NixOS root and isn't in git or on the shared
   data partition: `~/.ssh` (the installer can copy keys from Pop!_OS, if Pop
   has the same ones), shell history, browser profile (or rely on browser
   sync: saved passwords are encrypted per system), app data you care about.
3. Steam games and Proton prefixes (game saves) on the shared data partition
   are not touched; after the reinstall add that library again in
   Steam → Settings → Storage.
4. Pick a strong LUKS passphrase and store it safely (password manager or
   paper): **if it's lost, the data is gone.**

### 4. Reinstall (from Pop!_OS)

1. On Pop!_OS, get this repo's `main` (`git pull`), then check the partition
   names there (`lsblk -f`): the NixOS EFI partition is `NIXBOOT`, the NixOS
   one is labelled `nixos`; the shared data partition and Pop's NVMe must not
   be picked.
2. Run the guided installer: the SATA disk, "Delete some partitions, keep the
   others", tick the NixOS EFI (`NIXBOOT`) and NixOS (`nixos`) partitions only,
   then "Encrypt" (the first choice):
   ```bash
   bash nixos/install-from-linux.sh
   ```
   or directly (device names as shown by `lsblk` on Pop!_OS):
   ```bash
   bash nixos/install-from-linux.sh --boot-part /dev/<nixos-efi> --root-part /dev/<nixos-root> --encrypt
   ```
   The summary must say `Storage   encrypted: LUKS2 ...` and list the shared
   data partition as `Kept`; the last screen says `Deleting:` with the two NixOS
   partitions only (the command-line form formats them in place instead). Pop!_OS's disk and the shared data
   partition are untouched.
3. First boot: the Plymouth splash asks for the LUKS passphrase (works with
   the NVIDIA settings in `gpu.nix`: driver in the initrd, `nvidia_drm.fbdev=1`,
   simpledrm off), then the Caelestia lock screen. If Plymouth ever fails to start,
   the same prompt appears as plain text on the console. The initrd uses
   the US keyboard layout unless `console.keyMap` says otherwise; mind that
   for passphrases with special characters.

### 5. Verify

```bash
lsblk -f                            # root partition: crypto_LUKS -> cryptroot -> btrfs
sudo cryptsetup luksDump /dev/<root-part>
sudo btrfs subvolume list /
findmnt -t btrfs                    # subvol=, compress=zstd, noatime
```

Add a second passphrase keyslot kept offline: `sudo cryptsetup luksAddKey /dev/<root-part>`.

---

## On hold: Secure Boot + TPM auto-unlock

Not part of phase 1. Notes for when it's picked up (no reinstall needed).

### Secure Boot (Limine's built-in support)

No reinstall: config change + firmware steps.

1. `sbctl create-keys` (keys in `/var/lib/sbctl`, on the encrypted disk).
2. The boot loader is Limine, whose NixOS module signs its files with sbctl:
   set `boot.loader.limine.secureBoot.enable = true;` and rebuild.
   `sbctl verify` should show NixOS's files as signed. (lanzaboote is the
   alternative, but it replaces the boot loader with signed systemd-boot.)
3. Solve Pop!_OS first (see "Pop!_OS and Secure Boot"; option 1 = sign its
   files and add the re-sign hook on Pop).
4. Firmware: put Secure Boot into setup mode (clear the platform keys), boot
   NixOS, `sbctl enroll-keys --microsoft` (keeps Microsoft's keys: the
   GPU's firmware and other vendor code need them), then turn Secure Boot on
   and set a firmware (BIOS) password.
5. `bootctl status` → `Secure Boot: enabled`. Boot Pop!_OS once to confirm.

### TPM auto-unlock

Only after Secure Boot is on.

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/<root-part>
sudo systemd-cryptenroll --recovery-key /dev/<root-part>   # store it offline
```

```nix
boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [ "tpm2-device=auto" ];
```

Rebuild, reboot: no passphrase prompt; the Caelestia lock at boot (unchanged
since phase 1) is then the only password.
Keep the boot menu editor off (`boot.loader.limine.enableEditor`, off by
default; with it on, `init=/bin/sh` at the menu would get a root shell after
the TPM unlocked the disk). After a firmware update or
TPM reset the prompt comes back: unlock with the passphrase or recovery key,
then re-run the enroll command.

---

## Phase 2: move NixOS to the NVMe (after removing Pop!_OS)

Goal: the NVMe holds all of NixOS (EFI + encrypted Btrfs); the SATA disk keeps
only the shared/backup data. The system keeps running during the data move.

### 1. Before

- Back up anything you still need from Pop!_OS (its disk gets wiped).
- Fresh backup of NixOS-only data (same list as phase 1).
- With Pop!_OS gone, its signing hook and copied Secure Boot keys go with it.

### 2. Repartition the NVMe

Wipe it and create, from scratch (don't reuse Pop's ~500 MB EFI partition: NixOS
keeps a kernel + initrd per generation there, and with the NVIDIA driver in the
initrd those are large):

1. **EFI partition, 1 GiB**, FAT32 (`mkfs.fat -F 32 -n NIXBOOT2`)
2. **The rest: LUKS2** (same passphrase), opened as `cryptnvme`

```bash
sudo cryptsetup luksFormat --type luks2 --label nixos-crypt-nvme /dev/<nvme-root-part>
sudo cryptsetup open /dev/<nvme-root-part> cryptnvme
```

### 3. Move the data (online)

```bash
sudo btrfs device add /dev/mapper/cryptnvme /
sudo btrfs device remove /dev/mapper/cryptroot /   # migrates everything off the SATA partition
sudo btrfs filesystem show /                        # only cryptnvme left
```

The Btrfs filesystem keeps its UUID, so the `/`, `/home`, `/nix`,
`/var/log` mounts don't change. Don't leave both devices in the filesystem
long term (losing either disk would lose everything); the add → remove pair is
only a bridge.

### 4. Point the config at the NVMe

- LUKS: replace the `boot.initrd.luks.devices."cryptroot"` entry with the
  NVMe partition (by UUID; `blkid /dev/<nvme-root-part>`).
- Boot partition: mount the new EFI partition, copy the current `/boot`
  contents to it, and point `fileSystems."/boot"` at its UUID.
- Rebuild with the boot loader reinstalled onto the new EFI partition
  (`sudo nixos-rebuild switch --install-bootloader ...`); this creates a new
  firmware boot entry. With Secure Boot on, check `sbctl verify`.
- If TPM unlock is in use by then, enroll it on the new LUKS partition and add a recovery key.

### 5. Reboot and clean up

1. Reboot, pick the new boot entry, confirm `lsblk -f` shows NixOS running from
   the NVMe only.
2. Then (and only then) remove the old firmware entry and the SATA disk's
   old NixOS EFI and LUKS partitions; grow the shared/backup data partition
   into the freed space (`growpart` / `parted` + `resize2fs` for ext4).
3. Remove stale firmware entries for OSes that are gone.

Until step 2 you can still boot the old way from the SATA disk if something is
off.
