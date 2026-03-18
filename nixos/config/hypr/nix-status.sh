#!/usr/bin/env bash
# Waybar custom module — NixOS generation + store info
GEN=$(ls -d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l)
STORE=$(du -sh /nix/store 2>/dev/null | cut -f1)
CURRENT=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*' || echo "?")
printf '{"text":"󱄅 %s","tooltip":"Current generation: %s\\nTotal generations: %s\\nNix store: %s","class":""}\n' \
    "$CURRENT" "$CURRENT" "$GEN" "$STORE"
