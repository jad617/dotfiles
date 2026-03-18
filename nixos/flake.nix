{
  description = "NixOS Hyprland workstation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    sysc-greet.url = "github:Nomadcxx/sysc-greet";
  };

  outputs = { self, nixpkgs, neovim-nightly-overlay, sysc-greet, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ neovim-nightly-overlay.overlays.default ]; }
        sysc-greet.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
