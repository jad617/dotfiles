# =============================================================================
# Host: hashirama — i7-8700K + GTX 1070
# The GPU driver is picked by gpu.nix from the detected card (GTX 1070 = Pascal:
# proprietary 580 driver, the last series that supports it).
# =============================================================================
{ ... }: {
  networking.hostName = "hashirama";
}
