#!/usr/bin/env bash
# =============================================================================
# Copies SSH keys (and config / known_hosts) from this system's ~/.ssh into
# the new system's home. Used by install-from-linux.sh; optional, you pick the
# items. Keys stay on this machine: they go from ~/.ssh straight to the new
# disk, with the permissions ssh requires (folder 700, private keys 600).
#
#   copy-ssh.sh --list [SRC]                    one line per item: NAME<TAB>DESCRIPTION
#   copy-ssh.sh SRC DEST UID:GID NAME...        copy those items from SRC into DEST (run as root)
#
# Items: each key pair (the private key with its .pub, or a private key
# alone), config, known_hosts, authorized_keys, allowed_signers. Not copied:
# *.old backups, agent sockets and control sockets, folders.
# =============================================================================
set -euo pipefail

is_private_key() { head -c 64 "$1" 2>/dev/null | grep -q -- '-----BEGIN .*PRIVATE KEY-----'; }
EXTRAS=(config known_hosts authorized_keys allowed_signers)

list() { # SRC -> NAME<TAB>DESCRIPTION
    local src=$1 f name desc enc
    [[ -d $src ]] || return 0
    for f in "$src"/*; do
        [[ -f $f && ! -L $f ]] || continue
        name=$(basename "$f")
        [[ $name == *.pub || $name == *.old ]] && continue
        if is_private_key "$f"; then
            desc=""
            [[ -f $f.pub ]] && desc=$(ssh-keygen -l -f "$f.pub" 2>/dev/null | awk '{ c = ""; for (i = 3; i < NF; i++) c = c (c ? " " : "") $i; t = $NF; gsub(/[()]/, "", t); print t, $1 "-bit" (c ? ", " c : "") }' || true)
            enc=""
            ssh-keygen -y -P "" -f "$f" >/dev/null 2>&1 || enc=", passphrase-protected"
            printf '%s\tkey%s  %s%s\n' "$name" "$([[ -f $f.pub ]] && echo " + .pub")" "${desc:-private key}" "$enc"
        elif printf '%s\n' "${EXTRAS[@]}" | grep -qx "$name"; then
            printf '%s\t%s (%s lines)\n' "$name" "$name" "$(wc -l <"$f" | tr -d ' ')"
        fi
    done
}

if [[ ${1:-} == --list ]]; then
    list "${2:-$HOME/.ssh}"
    exit 0
fi

SRC=${1:?usage: $0 --list [SRC] | SRC DEST UID:GID NAME...} DEST=${2:?} OWNER=${3:?}
shift 3
((EUID == 0)) || { echo "run as root (it writes into the new system)" >&2 && exit 1; }
valid=$(list "$SRC" | cut -f1)
install -d -m 700 -o "${OWNER%:*}" -g "${OWNER#*:}" "$DEST"
for name in "$@"; do
    grep -qxF "$name" <<<"$valid" || { echo "  skipped $name: not a key or ssh file in $SRC" && continue; }
    install -m 600 -o "${OWNER%:*}" -g "${OWNER#*:}" "$SRC/$name" "$DEST/$name"
    if [[ -f $SRC/$name.pub ]] && is_private_key "$SRC/$name"; then
        install -m 644 -o "${OWNER%:*}" -g "${OWNER#*:}" "$SRC/$name.pub" "$DEST/$name.pub"
    fi
    echo "  copied ~/.ssh/$name$([[ -f $SRC/$name.pub ]] && is_private_key "$SRC/$name" && echo " (+ .pub)")"
done
