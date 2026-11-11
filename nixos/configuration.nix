# =============================================================================
# NixOS Hyprland workstation — shared base configuration
#
# Placeholders replaced by nixos/init.sh:
#   YOUR_USERNAME → your actual username
#   YOUR_TIMEZONE → e.g. America/Toronto
#
# Host-specific config (hostname, GPU drivers) lives in hosts/
# =============================================================================
{ config, pkgs, lib, ... }:

let
  # Steam and Google Chrome only exist for x86_64 (the arm64 VM gets Chromium)
  isX86 = pkgs.stdenv.hostPlatform.isx86_64;

  # ── Auto-detect boot mode ──────────────────────────────────────────────────
  isEfi = builtins.pathExists "/sys/firmware/efi";

  # ── Auto-detect boot disk (for GRUB on BIOS systems) ──────────────────────
  # Tries common disk names in order; first match wins.
  grubDisk =
    let candidates = builtins.filter (d: builtins.pathExists d)
          [ "/dev/vda" "/dev/sda" "/dev/nvme0n1" "/dev/vdb" "/dev/sdb" "/dev/hda" ];
    in if candidates != [] then builtins.head candidates else "nodev";

in {
  imports = [ ./hardware-configuration.nix ./gpu.nix ];   # gpu.nix: NVIDIA / AMD from detect-gpu.sh

  # ---------------------------------------------------------------------------
  # Boot
  # ---------------------------------------------------------------------------
  # Auto-detected: systemd-boot on UEFI, GRUB on BIOS/MBR
  boot.loader.systemd-boot.enable      = isEfi;
  boot.loader.systemd-boot.configurationLimit = 3;   # boot menu: last 3 generations
  boot.loader.grub.configurationLimit         = 3;
  boot.loader.efi.canTouchEfiVariables = isEfi;
  boot.loader.grub.enable              = !isEfi;
  boot.loader.grub.device              = grubDisk;
  boot.loader.grub.useOSProber         = false;
  # Use latest kernel (matches NixOS ISO default)
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # Host-specific kernelParams (e.g. NVIDIA) are set in hosts/

  # ---------------------------------------------------------------------------
  # Networking
  # ---------------------------------------------------------------------------
  networking = {
    # hostName is set per-host in hosts/vm.nix or hosts/hashirama.nix
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
  # Display Manager — Ly (TUI DM, nixpkgs) — Catppuccin Macchiato
  # ---------------------------------------------------------------------------
  services.displayManager = {
    defaultSession = "hyprland";
    ly = {
      enable = true;
      settings = {
        # Catppuccin Macchiato: 0xSSRRGGBB (SS = styling bits)
        bg       = "0x0024273a"; # Base
        fg       = "0x00cad3f5"; # Text
        border_fg = "0x00c6a0f6"; # Mauve
        error_fg = "0x01ed8796"; # Red + bold
        error_bg = "0x0024273a"; # Base
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Audio — PipeWire
  # ---------------------------------------------------------------------------
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = isX86;
    pulse.enable      = true;
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
  users.users."YOUR_USERNAME" = {   # quoted: usernames may contain dots
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
    enable                       = isX86;
    remotePlay.openFirewall      = true;
    dedicatedServer.openFirewall = false;
  };
  programs.gamemode.enable = true;

  # ---------------------------------------------------------------------------
  # Nix — enable flakes permanently after first rebuild
  # ---------------------------------------------------------------------------
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store   = true;
  # Prebuilt packages from nix-community, e.g. neovim-nightly (else built from source)
  nix.settings.extra-substituters       = [ "https://nix-community.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
  # Keep the last 3 system generations (rebuilds), whatever their age: drop the
  # older ones, then collect what nothing references any more
  nix.gc = {
    automatic = true;
    dates     = "weekly";
  };
  systemd.services.nix-gc.preStart =
    "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +3";

  # ---------------------------------------------------------------------------
  # Shell
  # ---------------------------------------------------------------------------
  programs.zsh.enable = true;
  # ~/.zshrc runs compinit with a daily cache; the global one in /etc/zshrc
  # would rebuild the completion dump on every new shell (~0.2 s)
  programs.zsh.enableGlobalCompInit = false;

  # ---------------------------------------------------------------------------
  # Packages
  # ---------------------------------------------------------------------------
  nixpkgs.config.allowUnfree = true;   # NVIDIA, etc.

  environment.systemPackages = with pkgs; [
    # ── Hyprland ecosystem ────────────────────────────────────────────────────
    caelestia-shell      # Caelestia: bar, launcher, notifications, lock, wallpaper, idle
    caelestia-cli        # `caelestia` command (shell, wallpaper, clipboard, ...)
    hyprmod              # Hyprland settings GUI (saves to config/hypr/hyprland-gui.lua)
    fuzzel               # picker used by `caelestia clipboard` / `caelestia emoji`
    hyprcursor
    hyprutils
    wl-clipboard
    cliphist
    wlsunset             # blue light filter / night mode
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
    # same tools init.sh installs on Pop!_OS / macOS
    tmux
    zellij
    lazygit
    yq-go                # mikefarah's yq (the one brew installs)
    wtype                # type text on Wayland
    pipx
    p7zip
    nmap
    mtr
    ipcalc
    gnupg

    # ── Dev ───────────────────────────────────────────────────────────────────
    neovim               # nightly via neovim-nightly-overlay

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
    (python3.withPackages (ps: with ps; [ pip pynvim pygobject3 ]))
    go                   # latest stable Go from nixpkgs-unstable
    rustup
    uv                   # fast Python package manager
    deno
    tree-sitter          # CLI, used by nvim-treesitter to compile parsers

    # ── DevOps (mirrors other workstations) ───────────────────────────────────
    awscli2
    terraform
    vault
    terraform-docs
    kubectl
    kubernetes-helm
    k9s
    ansible
    mysql84              # MySQL client (mysql, mysqldump, etc.; 8.0 was removed at EOL)
    gh                   # GitHub CLI  — run: gh extension install github/gh-copilot
    claude-code          # Claude Code CLI
    github-copilot-cli   # Copilot CLI (`copilot`, npm @github/copilot elsewhere)
    azure-cli
    eksctl
    argocd
    actionlint
    trivy
    maven
    dotnet-sdk_10        # .NET 10 LTS (8 reached end of support 2026-11-10)

    # ── GUI apps ──────────────────────────────────────────────────────────────
    (if isX86 then google-chrome else chromium)
    nautilus             # file manager
    gnome-calendar       # calendar (launch from wofi or click clock)
    (catppuccin-gtk.override { accents = [ "mauve" ]; variant = "macchiato"; })
    papirus-icon-theme          # much better folder/file icons
    adwaita-icon-theme          # provides Adwaita cursor theme
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
      # Caelestia shell
      material-symbols
      rubik
      nerd-fonts.caskaydia-cove
    ];
    fontconfig.defaultFonts = {
      monospace = [ "MesloLGS NF" ];
      sansSerif = [ "Noto Sans" ];
      serif     = [ "Noto Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Environment — Wayland + app defaults
  # (NVIDIA-specific vars are added per-host in hosts/hashirama.nix)
  # ---------------------------------------------------------------------------
  environment.sessionVariables = {
    XDG_SESSION_TYPE         = "wayland";

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
    BROWSER  = if isX86 then "google-chrome-stable" else "chromium";

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
  services.upower.enable       = true;    # battery / power info for Caelestia
  services.power-profiles-daemon.enable = true;  # Caelestia power profile toggle

  # ---------------------------------------------------------------------------
  system.stateVersion = "24.11";
}
