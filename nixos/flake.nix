{
  description = "NixOS Hyprland workstation";

  nixConfig = {
    extra-substituters      = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, neovim-nightly-overlay, noctalia, ... }@inputs:
  let
    system = "x86_64-linux";

    sharedModules = [
      {
        nixpkgs.overlays = [
          neovim-nightly-overlay.overlays.default
        ];
      }
      (./configuration.nix)
      # Pass noctalia package via specialArgs
      { environment.systemPackages = [ noctalia.packages.${system}.default ]; }
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
