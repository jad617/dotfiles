#!/usr/bin/env bash
# =============================================================================
# wallpaper.sh — set wallpaper via swww
# Called by hyprland exec-once
# =============================================================================

WALLPAPER="${1:-$HOME/Pictures/Wallpapers/quasar.webp}"

# Start daemon, ignore error if already running
swww-daemon &>/dev/null &
sleep 2

swww img "$WALLPAPER" --transition-type fade --transition-duration 1
