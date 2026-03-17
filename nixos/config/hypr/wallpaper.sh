#!/usr/bin/env bash
# =============================================================================
# wallpaper.sh — set wallpaper on all monitors dynamically via swww
# Called by hyprland exec-once
# =============================================================================

WALLPAPER="${1:-$HOME/Pictures/Wallpapers/quasar.webp}"

# Start daemon (newer swww uses 'swww daemon', older used 'swww-daemon')
if command -v swww-daemon &>/dev/null; then
  swww-daemon &
else
  swww daemon &
fi
sleep 1

# Apply to every connected monitor
hyprctl monitors -j | \
  grep -o '"name":"[^"]*"' | \
  cut -d'"' -f4 | \
  while read -r monitor; do
    swww img "$WALLPAPER" \
      --outputs "$monitor" \
      --transition-type fade \
      --transition-duration 1
  done
