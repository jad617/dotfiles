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
  # Steam, Google Chrome and Spotify only exist for x86_64 (the arm64 VM gets Chromium)
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
  # Auto-detected: Limine on UEFI (themed menu), GRUB on BIOS/MBR
  boot.loader.limine = {
    enable         = isEfi;
    maxGenerations = 3;                 # boot menu: last 3 generations
    # enableEditor stays off (default): editing entries would allow init=/bin/sh
    # Also put Limine at the firmware's fallback path (EFI/BOOT/BOOT*.EFI), so
    # NixOS still boots if the firmware forgets its boot entries (BIOS reset)
    extraInstallCommands = ''
      esp=${config.boot.loader.efi.efiSysMountPoint}
      ${pkgs.coreutils}/bin/mkdir -p "$esp/EFI/BOOT"
      for f in "$esp"/EFI/limine/BOOT*.EFI; do
        if [ -e "$f" ]; then ${pkgs.coreutils}/bin/cp "$f" "$esp/EFI/BOOT/"; fi
      done
    '';
    style = {
      # NixOS-logo pattern in Catppuccin Macchiato, to match the Plymouth splash
      wallpapers     = [ pkgs.nixos-artwork.wallpapers.nineish-catppuccin-macchiato.gnomeFilePath ];
      wallpaperStyle = "stretched";
      interface = {
        branding        = "NixOS";
        brandingColor   = "c6a0f6";     # Mauve
        helpColor       = "8aadf4";     # Blue
        helpColorBright = "a6da95";     # Green (countdown)
      };
      graphicalTerminal = {
        foreground    = "cad3f5";       # Text
        palette       = "494d64;ed8796;a6da95;eed49f;8aadf4;f5bde6;8bd5ca;b8c0e0";
        brightPalette = "5b6078;ed8796;a6da95;eed49f;8aadf4;f5bde6;8bd5ca;a5adcb";
      };
    };
  };
  boot.loader.grub.configurationLimit         = 3;
  boot.loader.efi.canTouchEfiVariables = isEfi;
  boot.loader.grub.enable              = !isEfi;
  boot.loader.grub.device              = grubDisk;
  boot.loader.grub.useOSProber         = false;
  # Use latest kernel (matches NixOS ISO default)
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # Host-specific kernelParams (e.g. NVIDIA) are set in hosts/

  # Polished boot: menu for 2 s (dual boot), then a Catppuccin splash instead
  # of kernel text (the initrd is systemd-based, so the handover is smooth);
  # gpu.nix loads the GPU driver early so the splash has the full resolution.
  boot.loader.timeout = 2;
  boot.plymouth = {
    enable = true;
    theme  = "catppuccin-macchiato";
    themePackages = [ (pkgs.catppuccin-plymouth.override { variant = "macchiato"; }) ];
  };
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet" "splash"
    "loglevel=3" "rd.udev.log_level=3" "udev.log_priority=3"
    "rd.systemd.show_status=auto"
    "vt.global_cursor_default=0"   # no blinking text cursor before/after the splash
  ];

  # ---------------------------------------------------------------------------
  # Networking
  # ---------------------------------------------------------------------------
  networking = {
    # hostName is set per-host in hosts/<host>.nix (hashirama.nix, utm.nix)
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
  # Login — Caelestia's lock screen is the login screen
  # ---------------------------------------------------------------------------
  # greetd logs straight into Hyprland once per boot (initial_session) with
  # CAELESTIA_AUTOLOCK=1, and hyprland.lua locks with Caelestia before anything
  # else starts; if the lock can't be confirmed it logs out instead.
  # After a logout, greetd shows tuigreet (text login) as the fallback.
  # Hyprland's stdout/stderr (startup debug lines, Xwayland's xkbcomp warnings)
  # go to the journal (journalctl -t hyprland) instead of the console, where
  # they showed between the splash and the lock screen.
  services.greetd = let
    hyprland = "${pkgs.systemd}/bin/systemd-cat -t hyprland ${config.programs.hyprland.package}/bin/start-hyprland";
  in {
    enable = true;
    settings = {
      initial_session = {
        user    = "YOUR_USERNAME";
        command = "env CAELESTIA_AUTOLOCK=1 ${hyprland}";
      };
      default_session = {
        user    = "greeter";
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --cmd '${hyprland}'";
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
  # Key Remapping — Capslock → a  (mirrors keyd on Pop!_OS); F1 / F2 are
  # monitor brightness down / up; F11 / F12 are
  # mute / volume down without Fn (the Logitech keyboard has them on Fn + F11 /
  # Fn + F12, while volume up is its own key). Plain F11 / F12 are never used
  # ---------------------------------------------------------------------------
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        capslock = "a";
        f1       = "brightnessdown";   # monitors over DDC/CI, via Caelestia
        f2       = "brightnessup";
        f11      = "mute";
        f12      = "volumedown";
      };
    };
  };

  # Monitor brightness over DDC/CI (desktop screens have no backlight device):
  # Caelestia's brightness keys run ddcutil on /dev/i2c-*. uaccess gives the
  # logged-in user access right away, no i2c group / re-login needed
  hardware.i2c.enable = true;
  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", SUBSYSTEM=="i2c-dev", TAG+="uaccess"
  '';

  # ---------------------------------------------------------------------------
  # Polkit agent (runs as a systemd user service, started by Hyprland session)
  # ---------------------------------------------------------------------------
  security.polkit.enable = true;
  systemd.user.services.polkit-agent = {
    description = "Polkit authentication agent";
    wantedBy    = [ "graphical-session.target" ];
    partOf      = [ "graphical-session.target" ];
    # No start limit: when Hyprland restarts (e.g. after a crash) the agent
    # fails until the new display is up, and 5 quick failures used to stop it
    # for good (no password prompts until the next login)
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart  = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart    = "on-failure";
      RestartSec = 2;
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

  # Btrfs installs (install-from-linux.sh --encrypt): read everything once a month
  # against its checksums, repairing metadata and reporting any damaged file
  services.btrfs.autoScrub = {
    enable   = (config.fileSystems."/".fsType or "") == "btrfs";
    interval = "monthly";
  };

  # ---------------------------------------------------------------------------
  # Shell
  # ---------------------------------------------------------------------------
  programs.zsh.enable = true;

  # Dark mode + icon / cursor theme for GTK4 / libadwaita apps (they read dconf, not
  # settings.ini): system defaults, there from the first login; a user can still change them
  programs.dconf = {
    enable = true;
    profiles.user.databases = [{
      settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        icon-theme   = "Papirus-Dark";
        cursor-theme = "Adwaita";   # the one Hyprland uses (XCURSOR_THEME in hyprland.lua)
        cursor-size  = lib.gvariant.mkInt32 24;
      };
    }];
  };
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
    nwg-displays         # GUI to arrange monitors (writes config/hypr/monitors.conf)
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
    tflint               # Terraform linter, run by nvim as an LSP (tflint --langserver)
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
    brightnessctl        # backlight (laptops)
    ddcutil              # external monitors' brightness (DDC/CI), used by Caelestia
    playerctl            # media keys
    xdg-utils
  ] ++ lib.optionals isX86 [
    spotify              # music (x86_64 only; Caelestia's media panel controls it)
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
