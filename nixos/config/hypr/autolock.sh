#!/usr/bin/env bash
# Run by hyprland.lua after greetd's auto-login (CAELESTIA_AUTOLOCK=1): lock the
# session with Caelestia's lock screen, which then acts as the login screen.
#
# Fails closed: Hyprland's keybinds stay off (the "autolock" submap) until the
# lock is confirmed, and if it can't be confirmed in ~20 s, this logs out
# (greetd then shows its text login).
# Once locked: keybinds back on, then run the arguments (the rest of autostart).

for _ in $(seq 1 80); do
    if [[ "$(timeout 2 caelestia shell lock isLocked 2>/dev/null)" == "true" ]]; then
        hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null
        [[ $# -gt 0 ]] && exec "$@"
        exit 0
    fi
    timeout 2 caelestia shell lock lock >/dev/null 2>&1
    sleep 0.25
done

hyprctl dispatch 'hl.dsp.exit()' >/dev/null
