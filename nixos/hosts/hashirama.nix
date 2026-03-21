# =============================================================================
# Host: hashirama — i7-8700K + GTX 1070 (NVIDIA proprietary, Wayland)
# =============================================================================
{ config, pkgs, ... }: {
  networking.hostName = "hashirama";

  # NVIDIA kernel params — required for Wayland modesetting
  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

  # NVIDIA proprietary driver (GTX 10xx — too old for open kernel module)
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable          = true;
    powerManagement.enable      = true;
    powerManagement.finegrained = false;
    open                        = false;
    nvidiaSettings              = true;
    package                     = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.graphics = {
    enable      = true;
    enable32Bit = true;   # Steam / 32-bit OpenGL
  };

  # NVIDIA Wayland env vars — applied at session level so all apps inherit them
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME         = "nvidia";
    GBM_BACKEND               = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS   = "1";
    NVD_BACKEND               = "direct";
  };
}
