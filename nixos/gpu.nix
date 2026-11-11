# =============================================================================
# GPU drivers, picked from the GPUs init.sh detected (/etc/nixos/gpu.json,
# written by nixos/detect-gpu.sh). No NVIDIA / AMD GPU (VMs): Mesa defaults.
# =============================================================================
{ config, lib, pkgs, ... }:

let
  detected = ./gpu.json;
  gpu = if builtins.pathExists detected
    then builtins.fromJSON (builtins.readFile detected)
    else { nvidia = [ ]; amd = [ ]; };

  hasNvidia = gpu.nvidia != [ ];
  hasAmd    = gpu.amd != [ ];

  # PCI device IDs from 0x1e00 are Turing (GTX 16xx / RTX 20xx) and newer: they
  # use NVIDIA's open kernel module and the current driver. Older cards (Maxwell,
  # Pascal: GTX 9xx / 10xx) were dropped after the 580 series and need it.
  hexToInt = hex: (builtins.fromTOML "v = ${hex}").v;
  nvidiaModern = lib.all (id: hexToInt id >= 7680) gpu.nvidia; # 0x1e00
  nvidiaPkgs = config.boot.kernelPackages.nvidiaPackages;
in
{
  config = lib.mkMerge [
    {
      hardware.graphics = {
        enable      = true;
        enable32Bit = pkgs.stdenv.hostPlatform.isx86_64; # Steam / 32-bit games
      };
    }

    (lib.mkIf hasNvidia {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable          = true;    # required for Wayland
        powerManagement.enable      = true;    # keeps VRAM across suspend
        powerManagement.finegrained = false;
        open                        = nvidiaModern;
        nvidiaSettings              = true;
        package = if nvidiaModern then nvidiaPkgs.stable else nvidiaPkgs.legacy_580;
      };

      # Load the driver in the initrd so the Plymouth splash gets a full-resolution
      # framebuffer (nvidia_drm.fbdev) instead of a blank or low-res screen.
      # simpledrm is kept from starting: otherwise Plymouth starts on it, loses
      # the screen when NVIDIA takes over (~2 s later) and boot text shows
      # through; this way Plymouth waits for the NVIDIA screen.
      boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
      boot.kernelParams = [
        "nvidia_drm.fbdev=1"
        "initcall_blacklist=simpledrm_platform_driver_init"
      ];

      # Hardware video decode through VA-API
      hardware.graphics.extraPackages = [ pkgs.nvidia-vaapi-driver ];

      # Hyprland's NVIDIA page (wiki.hypr.land/Nvidia): these two, plus
      # NVD_BACKEND for nvidia-vaapi-driver
      environment.sessionVariables = {
        LIBVA_DRIVER_NAME         = "nvidia";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        NVD_BACKEND               = "direct";
      };
    })

    (lib.mkIf hasAmd {
      # amdgpu in the initrd: the right resolution from early boot. Mesa (RADV
      # Vulkan, radeonsi OpenGL + VA-API) comes with hardware.graphics
      hardware.amdgpu.initrd.enable = true;
      environment.sessionVariables.LIBVA_DRIVER_NAME = lib.mkIf (!hasNvidia) "radeonsi";
    })
  ];
}
