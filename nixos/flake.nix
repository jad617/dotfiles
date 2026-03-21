{
  description = "NixOS Hyprland workstation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    hyprpanel = {
      url = "github:Jas-SinghFSU/HyprPanel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, neovim-nightly-overlay, hyprpanel, ... }:
  let
    system = "x86_64-linux";

    sharedModules = [
      {
        nixpkgs.overlays = [
          neovim-nightly-overlay.overlays.default
          (final: prev: { hyprpanel = hyprpanel.packages.${prev.system}.default; })
        ];
      }
      ./configuration.nix
    ];

    mkHost = hostModule: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = sharedModules ++ [ hostModule ];
    };
  in {
    nixosConfigurations = {
      # VM (VirtualBox / VMware — no GPU)
      nixos      = mkHost ./hosts/vm.nix;

      # hashirama — i7-8700K + GTX 1070
      hashirama  = mkHost ./hosts/hashirama.nix;
    };
  };
}
