# =============================================================================
# NixOS Hyprland workstation — GTX 1070
#
# Placeholders replaced by nixos/init.sh:
#   YOUR_USERNAME  → your actual username
#   YOUR_HOSTNAME  → your actual hostname
#   YOUR_TIMEZONE  → e.g. America/Toronto
# =============================================================================
{ config, pkgs, lib, ... }:

let
  # ── Auto-detect boot mode ──────────────────────────────────────────────────
  isEfi = builtins.pathExists "/sys/firmware/efi";

  # ── Auto-detect boot disk (for GRUB on BIOS systems) ──────────────────────
  # Tries common disk names in order; first match wins.
  grubDisk =
    let candidates = builtins.filter (d: builtins.pathExists d)
          [ "/dev/vda" "/dev/sda" "/dev/nvme0n1" "/dev/vdb" "/dev/sdb" "/dev/hda" ];
    in if candidates != [] then builtins.head candidates else "nodev";

in {
  imports = [ ./hardware-configuration.nix ];

  # ---------------------------------------------------------------------------
  # Boot
  # ---------------------------------------------------------------------------
  # Auto-detected: systemd-boot on UEFI, GRUB on BIOS/MBR
  boot.loader.systemd-boot.enable      = isEfi;
  boot.loader.efi.canTouchEfiVariables = isEfi;
  boot.loader.grub.enable              = !isEfi;
  boot.loader.grub.device              = grubDisk;
  boot.loader.grub.useOSProber         = false;
  # Use latest kernel (matches NixOS ISO default)
  boot.kernelPackages = pkgs.linuxPackages_latest;
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
  # Display Manager — LiDM (lightweight TUI, Catppuccin Macchiato)
  # ---------------------------------------------------------------------------
  services.lidm.enable = true;

  # ---------------------------------------------------------------------------
  # Audio — PipeWire
  # ---------------------------------------------------------------------------
  services.pulseaudio.enable = false;
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

  security.sudo.extraRules = [{
    users   = [ "YOUR_USERNAME" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

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
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 7d";  # keep last 7 days of generations
  };

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
    swaylock
    hypridle
    hyprcursor
    hyprutils
    waybar
    mako
    wofi
    wl-clipboard
    cliphist
    wlogout              # power menu (grid layout, replaces wofi powermenu)
    wlsunset             # blue light filter / night mode
    kanshi               # auto display profiles on monitor connect/disconnect
    nwg-displays         # GUI to generate kanshi profiles visually
    swww                 # wallpaper daemon (VM-friendly, dynamic monitor support)
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
    neovim               # nightly via neovim-nightly-overlay
    vimPlugins.nvim-treesitter.withAllGrammars  # treesitter parsers via nixpkgs (avoids TSUpdate issues)

    # ── LSP servers (replaces Mason on NixOS) ─────────────────────────────────
    ansible-language-server
    dockerfile-language-server
    helm-ls
    yaml-language-server
    basedpyright
    terraform-ls
    lua-language-server
    gopls

    # ── Linters & formatters (replaces Mason on NixOS) ────────────────────────
    stylua               # Lua
    shfmt                # shell
    shellcheck           # shell linter
    gofumpt              # Go formatter
    gotools              # goimports
    goimports-reviser    # Go import organizer
    golangci-lint        # Go linter
    ruff                 # Python formatter + linter
    markdownlint-cli     # Markdown linter
    yamllint             # YAML linter
    ansible-lint         # Ansible linter
    hadolint             # Dockerfile linter
    proselint            # prose linter
    nodejs
    nodePackages.npm
    (python3.withPackages (ps: with ps; [ pip pynvim pygobject3 ]))
    pkgs.go              # latest stable Go from nixpkgs-unstable
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
    google-chrome
    nautilus             # file manager
    gnome-calendar       # calendar (launch from wofi or click clock)
    (catppuccin-gtk.override { accents = [ "mauve" ]; variant = "macchiato"; })
    papirus-icon-theme          # much better folder/file icons
    gsettings-desktop-schemas   # required for gsettings icon-theme / color-scheme
    imv                  # image viewer
    mpv                  # video
    zathura              # PDF

    # ── Screenshot ────────────────────────────────────────────────────────────
    grimblast            # quick area/screen grabs (CLI, Hyprland-native)
    flameshot            # annotated screenshots (GUI, SUPER+SHIFT+S)

    # ── Nix tooling ───────────────────────────────────────────────────────────
    nix-output-monitor
    nixfmt

    # ── Build tools (needed by neovim plugins like LuaSnip) ──────────────────
    gnumake
    gcc
    pkg-config

    # ── Fetch / system info ───────────────────────────────────────────────────
    fastfetch            # popular neofetch replacement (fast, C-based)
    microfetch           # ultra-minimal fetch

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
      meslo-lgs-nf          # MesloLGS NF — used by WezTerm + oh-my-posh
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
    BROWSER  = "google-chrome-stable";

    # Force dark GTK theme for GTK3 apps
    GTK_THEME = "Catppuccin-Macchiato-Standard-Mauve-Dark";
    # Force dark mode for GTK4/libadwaita apps (Nautilus, GNOME Calendar)
    ADW_DEBUG_COLOR_SCHEME = "prefer-dark";
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
