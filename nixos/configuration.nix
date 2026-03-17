# =============================================================================
# NixOS Hyprland workstation — GTX 1070
#
# Placeholders replaced by nixos/init.sh:
#   YOUR_USERNAME  → your actual username
#   YOUR_HOSTNAME  → your actual hostname
#   YOUR_TIMEZONE  → e.g. America/Toronto
# =============================================================================
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ---------------------------------------------------------------------------
  # Boot
  # ---------------------------------------------------------------------------
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
  # Required for NVIDIA modesetting on Wayland
  boot.kernelParams = [ "nvidia_drm.modeset=1" "nvidia.NVreg_PreserveVideoMemoryAllocations=1" ];

  # ---------------------------------------------------------------------------
  # Networking
  # ---------------------------------------------------------------------------
  networking = {
    hostName = "YOUR_HOSTNAME";
    networkmanager.enable = true;
  };

  # ---------------------------------------------------------------------------
  # Locale & Time
  # ---------------------------------------------------------------------------
  time.timeZone = "YOUR_TIMEZONE";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS   = "en_US.UTF-8";
      LC_MONETARY  = "en_US.UTF-8";
      LC_PAPER     = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME      = "en_US.UTF-8";
    };
  };

  # ---------------------------------------------------------------------------
  # Hardware — NVIDIA GTX 1070 (Pascal / proprietary driver)
  # ---------------------------------------------------------------------------
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;          # needed for suspend/resume on Wayland
    powerManagement.finegrained = false;
    open = false;                           # proprietary kernel module (more stable for GTX 10xx)
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;                     # Steam / 32-bit OpenGL
  };

  # ---------------------------------------------------------------------------
  # Wayland / Hyprland
  # ---------------------------------------------------------------------------
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # XDG portals — screen sharing, file picker, etc.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # ---------------------------------------------------------------------------
  # Display Manager — greetd + tuigreet (minimal, no unnecessary GUI)
  # ---------------------------------------------------------------------------
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
      user    = "greeter";
    };
  };
  # Suppress greetd TTY switch message
  environment.etc."greetd/environments".text = "Hyprland\nbash\n";

  # ---------------------------------------------------------------------------
  # Audio — PipeWire
  # ---------------------------------------------------------------------------
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;
    pulse.enable      = true;
    jack.enable       = true;
  };

  # ---------------------------------------------------------------------------
  # Bluetooth
  # ---------------------------------------------------------------------------
  hardware.bluetooth = {
    enable       = true;
    powerOnBoot  = true;
    settings.General.Experimental = true;
  };
  services.blueman.enable = true;

  # ---------------------------------------------------------------------------
  # Key Remapping — Capslock → a  (mirrors keyd on Pop!_OS)
  # ---------------------------------------------------------------------------
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main.capslock = "a";
    };
  };

  # ---------------------------------------------------------------------------
  # Polkit agent (runs as a systemd user service, started by Hyprland session)
  # ---------------------------------------------------------------------------
  security.polkit.enable = true;
  systemd.user.services.polkit-agent = {
    description = "Polkit authentication agent";
    wantedBy    = [ "graphical-session.target" ];
    partOf      = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart   = "on-failure";
    };
  };

  # ---------------------------------------------------------------------------
  # User
  # ---------------------------------------------------------------------------
  users.users.YOUR_USERNAME = {
    isNormalUser = true;
    description  = "YOUR_USERNAME";
    extraGroups  = [ "networkmanager" "wheel" "audio" "video" "input" "gamemode" ];
    shell        = pkgs.zsh;
  };

  # ---------------------------------------------------------------------------
  # Steam
  # ---------------------------------------------------------------------------
  programs.steam = {
    enable                       = true;
    remotePlay.openFirewall      = true;
    dedicatedServer.openFirewall = false;
  };
  programs.gamemode.enable = true;

  # ---------------------------------------------------------------------------
  # Nix — enable flakes permanently after first rebuild
  # ---------------------------------------------------------------------------
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store   = true;

  # ---------------------------------------------------------------------------
  # Shell
  # ---------------------------------------------------------------------------
  programs.zsh.enable = true;

  # ---------------------------------------------------------------------------
  # Packages
  # ---------------------------------------------------------------------------
  nixpkgs.config.allowUnfree = true;   # NVIDIA, etc.

  environment.systemPackages = with pkgs; [
    # ── Hyprland ecosystem ────────────────────────────────────────────────────
    hyprpaper
    hyprlock
    hypridle
    hyprcursor
    hyprutils
    waybar
    mako
    wofi
    wl-clipboard
    cliphist
    networkmanagerapplet
    kanshi               # auto display profiles on monitor connect/disconnect
    nwg-displays         # GUI to generate kanshi profiles visually
    blueman
    pavucontrol
    polkit_gnome

    # ── Terminal ──────────────────────────────────────────────────────────────
    wezterm
    zsh
    zsh-syntax-highlighting

    # ── Shell utilities ───────────────────────────────────────────────────────
    oh-my-posh
    zoxide
    eza
    bat
    fd
    ripgrep
    fzf
    jq
    htop
    btop
    wget
    curl
    unzip
    git
    pwgen
    watch

    # ── Dev ───────────────────────────────────────────────────────────────────
    neovim
    nodejs
    nodePackages.npm
    python3
    python3Packages.pip
    python3Packages.pynvim
    go
    rustup
    uv                   # fast Python package manager

    # ── DevOps (mirrors other workstations) ───────────────────────────────────
    awscli2
    terraform
    vault
    terraform-docs
    kubectl
    kubernetes-helm
    k9s
    ansible
    mysql80              # MySQL client (mysql, mysqldump, etc.)
    gh                   # GitHub CLI  — run: gh extension install github/gh-copilot
    claude-code          # Claude Code CLI

    # ── GUI apps ──────────────────────────────────────────────────────────────
    firefox
    google-chrome
    nautilus             # file manager
    imv                  # image viewer
    mpv                  # video
    zathura              # PDF

    # ── Screenshot ────────────────────────────────────────────────────────────
    grimblast            # quick area/screen grabs (CLI, Hyprland-native)
    flameshot            # annotated screenshots (GUI, SUPER+SHIFT+S)

    # ── Nix tooling ───────────────────────────────────────────────────────────
    nix-output-monitor
    nixfmt-rfc-style

    # ── System / misc ─────────────────────────────────────────────────────────
    fontconfig
    libnotify            # notify-send
    brightnessctl        # backlight (useful even on desktops for external panels)
    playerctl            # media keys
    xdg-utils
  ];

  # ---------------------------------------------------------------------------
  # Fonts
  # ---------------------------------------------------------------------------
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      nerd-fonts.meslo-lg
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      noto-fonts
      noto-fonts-color-emoji
      font-awesome
    ];
    fontconfig.defaultFonts = {
      monospace = [ "MesloLGS NF" ];
      sansSerif = [ "Noto Sans" ];
      serif     = [ "Noto Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Environment — NVIDIA + Wayland
  # ---------------------------------------------------------------------------
  environment.sessionVariables = {
    # NVIDIA Wayland
    LIBVA_DRIVER_NAME        = "nvidia";
    XDG_SESSION_TYPE         = "wayland";
    GBM_BACKEND              = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS  = "1";
    NVD_BACKEND              = "direct";       # hardware video decode

    # Electron / Chromium — force native Wayland
    NIXOS_OZONE_WL                = "1";
    ELECTRON_OZONE_PLATFORM_HINT  = "wayland";

    # Qt Wayland
    QT_QPA_PLATFORM               = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";

    # Java AWT fix
    _JAVA_AWT_WM_NONREPARENTING = "1";

    # Defaults
    EDITOR   = "nvim";
    TERMINAL = "wezterm";
    BROWSER  = "firefox";
  };

  # ---------------------------------------------------------------------------
  # Services
  # ---------------------------------------------------------------------------
  services.dbus.enable         = true;
  services.udev.enable         = true;
  services.gvfs.enable         = true;    # auto-mount
  services.tumbler.enable      = true;    # thumbnails
  services.openssh.enable      = true;

  # ---------------------------------------------------------------------------
  system.stateVersion = "24.11";
}
