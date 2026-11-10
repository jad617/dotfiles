#!/usr/bin/env bash
# =============================================================================
# Prints the machine's NVIDIA / AMD GPUs as JSON for nixos/gpu.nix:
#   {"nvidia":["0x1b81"],"amd":[]}     (PCI device IDs)
# init.sh and vm-install.sh save it as /etc/nixos/gpu.json. Nix can't read
# /sys itself (sysfs files report a 4 KiB size and builtins.readFile fails).
# =============================================================================
set -euo pipefail

nvidia=() amd=()
for dev in /sys/bus/pci/devices/*; do
    [[ -r $dev/class && $(<"$dev/class") == 0x03* ]] || continue # display controllers
    case $(<"$dev/vendor") in
    0x10de) nvidia+=("\"$(<"$dev/device")\"") ;;
    0x1002) amd+=("\"$(<"$dev/device")\"") ;;
    esac
done

join() {
    local IFS=,
    echo "$*"
}
printf '{"nvidia":[%s],"amd":[%s]}\n' "$(join ${nvidia[@]+"${nvidia[@]}"})" "$(join ${amd[@]+"${amd[@]}"})"
