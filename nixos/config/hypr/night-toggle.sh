#!/usr/bin/env bash
# Toggle wlsunset (night mode / blue light filter)
if pgrep -x wlsunset > /dev/null; then
    pkill wlsunset
else
    wlsunset -t 4500 -T 6500 &>/dev/null &
fi
# Signal waybar to refresh the night module
pkill -RTMIN+2 waybar
