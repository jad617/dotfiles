#!/usr/bin/env bash
# =============================================================================
# Settings menu — triggered from Waybar
# =============================================================================

AUDIO="󰕾  Audio"
NETWORK="󰤨  Network"
BLUETOOTH="󰂯  Bluetooth"
DISPLAY="󰍹  Display"
WALLPAPER="󰸉  Wallpaper"

CHOSEN=$(printf "%s\n" "$AUDIO" "$NETWORK" "$BLUETOOTH" "$DISPLAY" "$WALLPAPER" | \
    wofi --show dmenu \
         --prompt "" \
         --width 200 \
         --height 255 \
         --no-actions \
         --cache-file /dev/null \
         --style "$HOME/.config/wofi/style.css")

case "$CHOSEN" in
    "$AUDIO")     pavucontrol ;;
    "$NETWORK")   nm-connection-editor ;;
    "$BLUETOOTH") blueman-manager ;;
    "$DISPLAY")   nwg-displays ;;
    "$WALLPAPER")
        WALL=$(ls "$HOME/Pictures/Wallpapers/"*.{jpg,jpeg,png,webp} 2>/dev/null | \
               xargs -I{} basename {} | \
               wofi --show dmenu --prompt "Wallpaper" --width 300 --cache-file /dev/null)
        [[ -n "$WALL" ]] && "$HOME/.config/hypr/wallpaper.sh" "$HOME/Pictures/Wallpapers/$WALL"
        ;;
esac
