#!/usr/bin/env bash
# =============================================================================
# wallpaper.sh — set wallpaper via swww
# Called by hyprland exec-once
# =============================================================================

WALLPAPER="${1:-$HOME/Pictures/Wallpapers/quasar.webp}"

# Start daemon if not already running
if ! pgrep -x swww-daemon &>/dev/null; then
  swww-daemon &
  sleep 2
fi

# Apply wallpaper to all monitors (no --outputs = all)
swww img "$WALLPAPER" --transition-type fade --transition-duration 1
