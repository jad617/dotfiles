# shellcheck shell=bash
# =============================================================================
# Shared by everything that writes /etc/nixos from this checkout or rebuilds
# it: init.sh, lib/write-config.sh (installers), bin/nixos-sync and
# bin/nixos-update. Source it; it only defines functions.
#
#   nixos_flake_host NIXOS_DIR       print the flake host for this machine
#   nixos_write_config NIXOS_DIR DEST USER TIMEZONE
#                                    write the checkout's NixOS files into DEST
# =============================================================================

# The repo-managed part of /etc/nixos. The rest is the machine's own:
# hardware-configuration.nix (nixos-generate-config), gpu.json
# (lib/detect-gpu.sh) and flake.lock (nixos-update keeps it current)
NIXOS_CONFIG_FILES=(flake.nix configuration.nix gpu.nix)
NIXOS_CONFIG_DIRS=(hosts patches) # patches/: source patches the flake applies (e.g. Caelestia)

# Flake host: NIXOS_HOST, else the one named like this machine
# (hosts/<hostname>.nix), else the UTM VM on an arm64 Mac (nixos-arm).
# Prints it, or explains on stderr and returns 1.
nixos_flake_host() {
    local dir=$1 name
    name=$(hostname)
    if [[ -n ${NIXOS_HOST:-} ]]; then
        echo "$NIXOS_HOST"
    elif [[ -f $dir/hosts/$name.nix ]]; then
        echo "$name"
    elif [[ $(uname -m) == aarch64 ]]; then
        echo nixos-arm
    else
        echo "no flake host for '$name' (hosts: $(sed -n 's/^ *\([A-Za-z0-9_-]*\) *= *mkHost .*/\1/p' "$dir/flake.nix" | xargs))." >&2
        echo "Add nixos/hosts/$name.nix + an entry in nixos/flake.nix, or set NIXOS_HOST=<host>." >&2
        return 1
    fi
}

# Writes the checkout's files into DEST (an /etc/nixos, or a staging copy of
# one) with the placeholders filled in: YOUR_USERNAME, YOUR_TIMEZONE. Leaves
# DEST's other files alone. Fails if a placeholder is left unfilled.
nixos_write_config() {
    local dir=$1 dest=$2 user=$3 tz=$4 f d
    mkdir -p "$dest"
    for f in "${NIXOS_CONFIG_FILES[@]}"; do cp "$dir/$f" "$dest/$f"; done
    for d in "${NIXOS_CONFIG_DIRS[@]}"; do
        rm -rf "${dest:?}/$d"
        [[ -d $dir/$d ]] && cp -r "$dir/$d" "$dest/$d"
    done
    sed -i "s/YOUR_USERNAME/$user/g" "$dest/configuration.nix" "$dest/hosts/"*.nix
    sed -i "s|YOUR_TIMEZONE|$tz|g" "$dest/configuration.nix"
    if grep -rn 'YOUR_[A-Z]*' "$dest" --include='*.nix' >&2; then
        echo "placeholders left unfilled in $dest (above)" >&2
        return 1
    fi
}
