# =============================================================================
# Host: nixos-arm — NixOS VM on an Apple Silicon Mac (UTM / QEMU, aarch64)
# Created and installed by nixos/vm.sh, which also syncs the dotfiles into
# ~/nodestack/dotfiles over SSH (localhost:2222).
# =============================================================================
{ ... }: {
  networking.hostName = "nixos-arm";

  # GPU: virtio-gpu-gl (UTM renders OpenGL through Metal)
  hardware.graphics.enable = true;

  # virgl reports a legacy OpenGL 2.1 profile by default, so Qt asks for GLSL 1.20
  # shaders, which Caelestia doesn't ship: its bar and screen border never draw.
  # Report OpenGL 3.3 so Qt uses the GLSL 3.30 ones.
  environment.sessionVariables = {
    MESA_GL_VERSION_OVERRIDE   = "3.3COMPAT";
    MESA_GLSL_VERSION_OVERRIDE = "330";
  };

  # Clipboard sharing + dynamic resolution, and `utmctl ip-address`
  services.spice-vdagentd.enable = true;
  services.qemuGuest.enable      = true;

  # Kernel + login on the serial port too (vm.sh console)
  boot.kernelParams = [ "console=tty0" "console=ttyAMA0,115200" ];
}
