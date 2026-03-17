#!/usr/bin/env bash
# =============================================================================
# Power / session menu — triggered from Waybar
# =============================================================================

LOCK="  Lock"
LOGOUT="󰍃  Logout"
SUSPEND="󰒲  Suspend"
REBOOT="󰜉  Reboot"
SHUTDOWN="󰐥  Shutdown"

CHOSEN=$(printf "%s\n" "$LOCK" "$LOGOUT" "$SUSPEND" "$REBOOT" "$SHUTDOWN" | \
    wofi --show dmenu \
         --prompt "" \
         --width 180 \
         --height 230 \
         --no-actions \
         --cache-file /dev/null \
         --style "$HOME/.config/wofi/style.css")

case "$CHOSEN" in
    "$LOCK")     loginctl lock-session ;;
    "$LOGOUT")   hyprctl dispatch exit ;;
    "$SUSPEND")  systemctl suspend ;;
    "$REBOOT")   systemctl reboot ;;
    "$SHUTDOWN") systemctl poweroff ;;
esac
