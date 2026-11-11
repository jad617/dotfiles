# =============================================================================
# Host: hashirama — i7-8700K + GTX 1070
# The GPU driver is picked by gpu.nix from the detected card (GTX 1070 = Pascal:
# proprietary 580 driver, the last series that supports it).
# Dual boot: Pop!_OS on the NVMe, NixOS on sda2 (EFI) + sda3, data on sda1.
# =============================================================================
{ ... }: {
  networking.hostName = "hashirama";

  # Data partition shared with Pop!_OS; nofail so a missing disk never blocks boot
  fileSystems."/backup" = {
    device  = "/dev/disk/by-uuid/2c3a73fc-83cb-470b-8b57-ed1a361ad86c";
    fsType  = "ext4";
    options = [ "defaults" "nofail" ];
  };
}
