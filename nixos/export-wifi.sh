#!/usr/bin/env bash
# =============================================================================
# Copies Wi-Fi networks saved in this system's NetworkManager (Pop!_OS, or a
# live CD session) into another system, so it is online at its first boot.
# Used by install-from-linux.sh; run as root (reading the passwords needs it).
#
#   export-wifi.sh --list                 one line per saved Wi-Fi: UUID<TAB>NAME<TAB>ACTIVE(yes|no)
#   export-wifi.sh DEST_DIR UUID...       write those as NetworkManager keyfiles into DEST_DIR
#                                         (e.g. /mnt/etc/NetworkManager/system-connections)
#
# Each profile is rebuilt from its essentials (name, SSID, hidden, security,
# password), never copied as is: no BSSID lock (a network pinned to one access
# point fails when the router steers that card to another band), no MAC or
# interface name of this machine. Passwords stay on this machine: they go
# from this system's NetworkManager straight into DEST_DIR, mode 600.
# Supported: open, WPA/WPA2-Personal (wpa-psk), WPA3-Personal (sae). Skipped:
# enterprise networks (802.1X, their certificates live elsewhere) and WEP.
# =============================================================================
set -euo pipefail

command -v nmcli >/dev/null || { echo "nmcli not found: this system does not use NetworkManager" >&2 && exit 3; }

field() { # UUID FIELD -> value, nmcli's -g escaping (\: and \\) undone
    nmcli -s -g "$2" connection show "$1" 2>/dev/null | sed 's/\\\(.\)/\1/g'
}
keyfile_escape() { # GKeyFile string: \ -> \\, leading space -> \s
    local v=${1//\\/\\\\}
    [[ $v == " "* ]] && v="\\s${v:1}"
    printf '%s' "$v"
}

if [[ ${1:-} == --list ]]; then
    active=$(nmcli -t -g UUID connection show --active 2>/dev/null || true)
    nmcli -t -g UUID,TYPE connection show 2>/dev/null | while IFS=: read -r uuid type; do
        [[ $type == 802-11-wireless ]] || continue
        name=$(field "$uuid" connection.id)
        if grep -qx "$uuid" <<<"$active"; then a=yes; else a=no; fi
        printf '%s\t%s\t%s\n' "$uuid" "$name" "$a"
    done
    exit 0
fi

DEST=${1:?usage: $0 --list | DEST_DIR UUID...}
shift
((EUID == 0)) || { echo "run as root: the Wi-Fi passwords are only readable by root" >&2 && exit 1; }
install -d -m 700 "$DEST"
for uuid in "$@"; do
    name=$(field "$uuid" connection.id)
    [[ -n $name ]] || { echo "  skipped $uuid: no such connection" && continue; }
    auto=$(field "$uuid" connection.autoconnect)
    ssid=$(field "$uuid" 802-11-wireless.ssid)
    hidden=$(field "$uuid" 802-11-wireless.hidden)
    km=$(field "$uuid" 802-11-wireless-security.key-mgmt)
    psk=$(field "$uuid" 802-11-wireless-security.psk)
    case $km in
    "") sec="" ;; # open network
    none) echo "  skipped \"$name\": WEP is not copied" && continue ;;
    wpa-psk | sae)
        [[ -n $psk ]] || { echo "  skipped \"$name\": no saved password" && continue; }
        sec=$'\n'"[wifi-security]"$'\n'"key-mgmt=$km"$'\n'"psk=$(keyfile_escape "$psk")"$'\n'
        ;;
    *) echo "  skipped \"$name\": $km (enterprise) is not copied" && continue ;;
    esac
    out=$DEST/$uuid.nmconnection
    umask 077
    {
        printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\nautoconnect=%s\n\n' "$(keyfile_escape "$name")" "$uuid" "$([[ $auto == no ]] && echo false || echo true)"
        printf '[wifi]\nmode=infrastructure\nssid=%s\n' "$(keyfile_escape "$ssid")"
        [[ $hidden == yes ]] && printf 'hidden=true\n'
        printf '%s' "$sec"
        printf '\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\naddr-gen-mode=default\n'
    } >"$out"
    chmod 600 "$out"
    echo "  copied Wi-Fi \"$name\""
done
