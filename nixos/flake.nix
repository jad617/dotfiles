{
  description = "NixOS Hyprland workstation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # HyprMod (GTK settings app for Hyprland). nixpkgs has 0.4.0; 0.5.0 fixes
    # many Lua-config bugs, so use upstream's flake at the release tag
    hyprmod = {
      url = "github:BlueManCZ/hyprmod/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # WezTerm with per-split floating panes: the jad617 fork, same branch
    # init.sh builds on macOS / Pop!_OS. Update: nix flake update wezterm-src
    wezterm-src = {
      url = "git+https://github.com/jad617/wezterm?ref=floating-splits&submodules=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, neovim-nightly-overlay, caelestia-shell, hyprmod, wezterm-src, ... }:
  let
    sharedModules = [
      {
        nixpkgs.overlays = [
          neovim-nightly-overlay.overlays.default
          hyprmod.overlays.default
          (final: prev: let system = prev.stdenv.hostPlatform.system; in {
            caelestia-shell = caelestia-shell.packages.${system}.with-cli;
            # with-cli only puts `caelestia` on the shell's own PATH; Hyprland binds need it too
            caelestia-cli   = caelestia-shell.inputs.caelestia-cli.packages.${system}.default;

            # nixpkgs' wezterm recipe, built from the fork. Cargo deps come from
            # the fork's Cargo.lock, so updating the input needs no hash edits
            wezterm = prev.wezterm.overrideAttrs (_: {
              version   = "0-fork-${wezterm-src.shortRev}";
              src       = wezterm-src;
              cargoDeps = final.rustPlatform.importCargoLock {
                lockFile             = "${wezterm-src}/Cargo.lock";
                allowBuiltinFetchGit = true;
              };
            });
          })
        ];
      }
      ./configuration.nix
    ];

    mkHost = system: hostModule: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = sharedModules ++ [ hostModule ];
    };
  in {
    nixosConfigurations = {
      # VM (VirtualBox / VMware — no GPU)
      nixos      = mkHost "x86_64-linux" ./hosts/vm.nix;

      # VM on an Apple Silicon Mac (UTM, see nixos/vm.sh)
      nixos-arm  = mkHost "aarch64-linux" ./hosts/utm.nix;

      # hashirama — i7-8700K + GTX 1070
      hashirama  = mkHost "x86_64-linux" ./hosts/hashirama.nix;
    };
  };
}
