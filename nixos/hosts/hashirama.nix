# =============================================================================
# Host: hashirama — i7-8700K + GTX 1070
# The GPU driver is picked by gpu.nix from the detected card (GTX 1070 = Pascal:
# proprietary 580 driver, the last series that supports it).
# Dual boot: Pop!_OS on the NVMe, NixOS on sda2 (EFI) + sda3, data on sda1.
# =============================================================================
{ pkgs, lib, ... }:
let
  user = "YOUR_USERNAME";
  # Folders shared with Pop!_OS: one copy on /backup/shared, seen from both systems
  shared = [ "Pictures" "Downloads" "Documents" "Desktop" ];
in {
  networking.hostName = "hashirama";

  # The Intel Wireless 3165 (behind root port 00:1c.6) floods the journal with
  # correctable PCIe AER errors (~70k lines a boot) while link power saving
  # (ASPM) is on. Turning ASPM off stops them; the cost on a desktop is a few watts.
  boot.kernelParams = [ "pcie_aspm=off" ];

  # Pop!_OS in the Limine menu: hands off to Pop's own systemd-boot on the
  # NVMe's EFI partition (by partition GUID), so Pop's kernel updates
  # (kernelstub) keep working and none of Pop's files are touched.
  boot.loader.limine.extraEntries = ''
    /Pop!_OS
      protocol: efi
      path: guid(5e1e0a58-8622-46a8-a0e0-503b8390586c):/EFI/systemd/systemd-bootx64.efi
  '';

  # Never sleep: with the KVM on the other PC this one sees no input, idles,
  # and didn't wake back up (NVIDIA resume / no wake event through the KVM).
  # Caelestia only locks and blanks the screens on idle (config/caelestia/shell.json); this also
  # blocks suspend/hibernate from anything else (session menu, logind).
  systemd.sleep.settings.Sleep = {
    AllowSuspend              = "no";
    AllowHibernation          = "no";
    AllowHybridSleep          = "no";
    AllowSuspendThenHibernate = "no";
  };

  # Data partition shared with Pop!_OS; nofail so a missing disk never blocks boot
  fileSystems."/backup" = {
    device  = "/dev/disk/by-uuid/2c3a73fc-83cb-470b-8b57-ed1a361ad86c";
    fsType  = "ext4";
    options = [ "defaults" "nofail" ];
  };

  # ~/Pictures etc. -> /backup/shared/<name>, at every boot and rebuild (also after a
  # reinstall). Never deletes data: a real folder in the way is renamed <name>.local-<date>,
  # unless it holds no files at all (only links and empty folders, as a fresh install
  # leaves them), then it is cleared.
  system.activationScripts.sharedFolders = {
    deps = [ "users" ];
    text = ''
      PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.findutils ]}:$PATH
      home=/home/${user}
      if [ -d "$home" ]; then
        for d in ${lib.concatStringsSep " " shared}; do
          link=$home/$d target=/backup/shared/$d
          if [ -L "$link" ]; then
            [ "$(readlink "$link")" = "$target" ] && continue
            rm "$link"
          elif [ -d "$link" ] && [ -z "$(find "$link" -mindepth 1 ! -type l ! -type d -print -quit)" ]; then
            find "$link" -depth -mindepth 1 \( -type l -o -type d -empty \) -delete
            rmdir "$link" 2>/dev/null || mv "$link" "$link.local-$(date +%Y%m%d-%H%M%S)"
          elif [ -e "$link" ]; then
            mv "$link" "$link.local-$(date +%Y%m%d-%H%M%S)"
          fi
          ln -s "$target" "$link"
          chown -h ${user}:users "$link"
        done
      fi
    '';
  };
}
