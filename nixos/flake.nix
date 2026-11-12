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
            # Bar's active window: the app's name (WezTerm, Google Chrome), not
            # the window title, which changes with every split / tab / page
            caelestia-shell = caelestia-shell.packages.${system}.with-cli.overrideAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace modules/bar/components/ActiveWindow.qml \
                  --replace-fail 'import QtQuick' $'import QtQuick\nimport Quickshell' \
                  --replace-fail 'const title = Hypr.activeToplevel?.title;' \
                    'const cls = Hypr.activeToplevel?.lastIpcObject.class; const title = cls ? (DesktopEntries.heuristicLookup(cls)?.name || cls) : "";'
                # Bar popouts (status icons, tray menus) open on click, not
                # hover; a second click on the same icon closes it
                substituteInPlace modules/drawers/Interactions.qml \
                  --replace-fail 'bar.checkPopout(y);' '// click only: see onClicked' \
                  --replace-fail 'onPressed: event => dragStart = Qt.point(event.x, event.y)' \
                    $'onPressed: event => dragStart = Qt.point(event.x, event.y)\n    onClicked: event => { if (fullscreen || event.x >= bar.implicitWidth) return; const prev = popouts.hasCurrent ? popouts.currentName : ""; bar.checkPopout(event.y); if (prev !== "" && popouts.currentName === prev) popouts.hasCurrent = false; }'
                # Tray icons with a menu (Steam has no "open" action, only a menu)
                # let a left click through, so it opens that menu like hover did
                substituteInPlace modules/bar/components/TrayItem.qml \
                  --replace-fail 'acceptedButtons: Qt.LeftButton | Qt.RightButton' \
                    'acceptedButtons: modelData.hasMenu ? Qt.RightButton : (Qt.LeftButton | Qt.RightButton)'
                # A click on the bar's clock / calendar toggles the dashboard
                # on that screen, like SUPER + A
                substituteInPlace modules/bar/Bar.qml \
                  --replace-fail '} else if (id === "activeWindow"' \
                    '} else if (id === "clock") { popouts.hasCurrent = false; root.screenState.dashboard = !root.screenState.dashboard; } else if (id === "activeWindow"'
                # DDC/CI brightness about twice as fast: no read-back after
                # each change, shorter waits between I2C messages (0.3 was the
                # fastest the LG takes without retries; 0.1 made it slower)
                substituteInPlace services/Brightness.qml \
                  --replace-fail '["ddcutil", "-b", busNum, "setvcp", "10", rounded]' \
                    '["ddcutil", "-b", busNum, "setvcp", "10", rounded, "--noverify", "--sleep-multiplier", "0.3"]'
              '';
            });
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
      # VM on an Apple Silicon Mac (UTM, see nixos/vm/vm.sh)
      nixos-arm  = mkHost "aarch64-linux" ./hosts/utm.nix;

      # hashirama — i7-8700K + GTX 1070
      hashirama  = mkHost "x86_64-linux" ./hosts/hashirama.nix;
    };
  };
}
