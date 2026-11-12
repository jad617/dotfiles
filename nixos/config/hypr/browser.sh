#!/usr/bin/env bash
# SUPER + B: a new browser window with the cursor in the address bar.
# Chrome's New Tab page keeps the keyboard focus in the page, so once the new
# window has focus this sends it CTRL + L (focus the address bar). Gives up
# after ~5 s, e.g. if the browser didn't start.

before=$(hyprctl activewindow -j | jq -r '.address // ""')
"${BROWSER:-google-chrome-stable}" --new-window >/dev/null 2>&1 &
disown

for _ in $(seq 1 50); do
    sleep 0.1
    read -r addr cls < <(hyprctl activewindow -j | jq -r '"\(.address // "") \(.class // "")"')
    if [[ -n $addr && $addr != "$before" && $cls == *chrom* ]]; then
        sleep 0.4 # let the New Tab page take its focus first, then take it back
        hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"CTRL\", key = \"L\", window = \"address:$addr\" })" >/dev/null
        exit 0
    fi
done
