#!/usr/bin/env bash
# =============================================================================
# Writes <root>/etc/nixos from this checkout, for a NixOS install into <root>.
# Shared by vm/vm-install.sh (in the installer ISO) and install-from-linux.sh
# (from another distro). Runs as root with nixos-generate-config and nix on PATH.
#
#   write-config.sh <root> <user> <timezone>
# =============================================================================
set -euo pipefail

ROOT=$1 USERNAME=$2 TIMEZONE=$3
NIXOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" # nixos/ (this file is in nixos/lib)
ETC="$ROOT/etc/nixos"

nixos-generate-config --root "$ROOT"
cp "$NIXOS_DIR/flake.nix" "$NIXOS_DIR/configuration.nix" "$NIXOS_DIR/gpu.nix" "$ETC/"
[[ -f "$NIXOS_DIR/flake.lock" ]] && cp "$NIXOS_DIR/flake.lock" "$ETC/"
rm -rf "$ETC/hosts" "$ETC/patches" && cp -r "$NIXOS_DIR/hosts" "$ETC/hosts" && cp -r "$NIXOS_DIR/patches" "$ETC/patches"
bash "$NIXOS_DIR/lib/detect-gpu.sh" >"$ETC/gpu.json"
sed -i "s/YOUR_USERNAME/$USERNAME/g" "$ETC/configuration.nix" "$ETC/hosts/"*.nix
sed -i "s|YOUR_TIMEZONE|$TIMEZONE|g" "$ETC/configuration.nix"
echo "  GPU: $(cat "$ETC/gpu.json")"

# Lock first: adds inputs missing from flake.lock. If nixos-install wrote the
# lock itself, the flake's hash would change mid-build ("NAR hash mismatch")
nix --extra-experimental-features "nix-command flakes" flake lock "$ETC"
