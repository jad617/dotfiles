#!/usr/bin/env bash
# =============================================================================
# NixOS test VM on an Apple Silicon Mac (UTM, aarch64, no admin rights needed).
#
#   nixos/vm.sh install   create the VM and install the nixos-arm host from
#                         this checkout (uncommitted changes included)
#   nixos/vm.sh install --retry   after a failed install: run the installer
#                         again in the still-running ISO (no new VM, no click)
#   nixos/vm.sh rebuild   copy this checkout into the VM and run nixos/init.sh
#   nixos/vm.sh start | stop | status | ssh [cmd] | console | destroy
#
# The VM's SSH is forwarded to localhost:2222 and its serial console to
# localhost:4555. The installer runs over that serial console (no clicks).
#
#   VM_USER (default: jelasmar)
#   VM_PASSWORD (default: the "nixos-vm" item in your login Keychain; the first
#   install asks for one, or generates one, and saves it there, never in the repo)
#   VM_CPUS=8  VM_MEMORY_MB=16384  VM_DISK_GB=64  VM_TIMEZONE (default: Mac's)
#   NIXOS_VM_DIR=~/VMs  NIXOS_ISO_URL (default: latest stable minimal aarch64)
# =============================================================================
set -euo pipefail

NIXOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$(dirname "$NIXOS_DIR")"

VM_NAME=nixos-dotfiles
VM_DIR=${NIXOS_VM_DIR:-$HOME/VMs}
BUNDLE="$VM_DIR/$VM_NAME.utm"
CACHE="$HOME/.cache/nixos-vm"
ISO_URL=${NIXOS_ISO_URL:-https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-aarch64-linux.iso}
ISO="$CACHE/$(basename "$ISO_URL")"

VM_USER=${VM_USER:-jelasmar}
KEYCHAIN_ITEM=nixos-vm
VM_CPUS=${VM_CPUS:-8}
VM_MEMORY_MB=${VM_MEMORY_MB:-16384}
VM_DISK_GB=${VM_DISK_GB:-64}
VM_TIMEZONE=${VM_TIMEZONE:-$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')}
VM_TIMEZONE=${VM_TIMEZONE:-America/Toronto}

SSH_PORT=2222
SERIAL_PORT=4555
HTTP_PORT=4556
HTTP_PID=""

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || die "needs an Apple Silicon Mac"

# -----------------------------------------------------------------------------
# Tools
# -----------------------------------------------------------------------------
UTM_APP=""
for app in "$HOME/Applications/UTM.app" /Applications/UTM.app; do
    [[ -d $app ]] && UTM_APP=$app && break
done

ensure_tools() {
    if [[ -z $UTM_APP ]]; then
        info "Installing UTM into ~/Applications"
        mkdir -p "$HOME/Applications"
        brew install --cask utm --appdir "$HOME/Applications"
        UTM_APP="$HOME/Applications/UTM.app"
    fi
    if ! command -v qemu-img >/dev/null; then
        info "Installing qemu (for qemu-img)"
        brew install qemu
    fi
}

# The VM user's password lives in the macOS login Keychain, not in the repo:
#   security find-generic-password -s nixos-vm -w
vm_password() {
    [[ -n ${VM_PASSWORD:-} ]] && return
    VM_PASSWORD=$(security find-generic-password -s "$KEYCHAIN_ITEM" -a "$VM_USER" -w 2>/dev/null || true)
    [[ -n $VM_PASSWORD ]] && return
    if [[ -t 0 ]]; then
        local again
        read -rsp "Password for $VM_USER in the VM (empty = generate one): " VM_PASSWORD && echo
        if [[ -n $VM_PASSWORD ]]; then
            read -rsp "Again: " again && echo
            [[ $again == "$VM_PASSWORD" ]] || die "passwords do not match"
        fi
    fi
    if [[ -z $VM_PASSWORD ]]; then
        VM_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=')
        info "Generated a password for $VM_USER (show it: security find-generic-password -s $KEYCHAIN_ITEM -w)"
    fi
    security add-generic-password -U -s "$KEYCHAIN_ITEM" -a "$VM_USER" -w "$VM_PASSWORD" ||
        die "could not save the password to the Keychain"
}

ssh_key() {
    local k
    for k in "$HOME"/.ssh/id_ed25519.pub "$HOME"/.ssh/id_rsa.pub; do
        [[ -f $k ]] && cat "$k" && return
    done
    die "no SSH public key in ~/.ssh (run: ssh-keygen -t ed25519)"
}

SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR -o ConnectTimeout=5)
vm_ssh() { ssh "${SSH_OPTS[@]}" "$VM_USER@127.0.0.1" "$@"; }
vm_ssh_tty() { ssh -t "${SSH_OPTS[@]}" "$VM_USER@127.0.0.1" "$@"; }

# -----------------------------------------------------------------------------
# VM lifecycle (utmctl needs the Automation permission; fall back to clicking)
# -----------------------------------------------------------------------------
vm_running() { pgrep -qf "QEMULauncher.*$VM_NAME.utm" 2>/dev/null || nc -z 127.0.0.1 "$SERIAL_PORT" 2>/dev/null; }

vm_start() {
    [[ -d $BUNDLE ]] || die "no VM yet, run: $0 install"
    vm_running && return
    open -a "$UTM_APP" "$BUNDLE"
    sleep 3
    if ! utmctl start "$VM_NAME" >/dev/null 2>&1; then
        info "Press ▶ on \"$VM_NAME\" in UTM (utmctl is not allowed to control UTM)"
    fi
    local i
    for ((i = 0; i < 300; i++)); do
        nc -z 127.0.0.1 "$SERIAL_PORT" 2>/dev/null && return
        sleep 1
    done
    die "the VM did not start"
}

vm_stop() {
    vm_running || return 0
    if ! utmctl stop "$VM_NAME" >/dev/null 2>&1; then
        vm_ssh sudo poweroff >/dev/null 2>&1 || true
    fi
    local i
    for ((i = 0; i < 60; i++)); do
        vm_running || return 0
        sleep 1
    done
    info "Forcing the VM off"
    pkill -f "QEMULauncher.*$VM_NAME.utm" 2>/dev/null || true
    for ((i = 0; i < 30; i++)); do
        vm_running || return 0
        sleep 1
    done
    die "the VM is still running; stop it in UTM"
}

wait_for_ssh() {
    info "Waiting for SSH on localhost:$SSH_PORT"
    local i
    for ((i = 0; i < 300; i++)); do
        vm_ssh true 2>/dev/null && return
        sleep 2
    done
    die "SSH did not come up (see the VM window, or: $0 console)"
}

# -----------------------------------------------------------------------------
# UTM bundle (config.plist schema: UTM 5, ConfigurationVersion 4)
# -----------------------------------------------------------------------------
write_config() { # $1 = with ISO (1/0)
    python3 - "$BUNDLE/config.plist" "$1" "$VM_NAME" "$VM_CPUS" "$VM_MEMORY_MB" \
        "$SSH_PORT" "$SERIAL_PORT" <<'PY'
import os, plistlib, sys, uuid, random
path, with_iso, name, cpus, mem, ssh_port, serial_port = sys.argv[1:]
old = plistlib.load(open(path, "rb")) if os.path.exists(path) else {}
ident = lambda: str(uuid.uuid4()).upper()
mac = old.get("Network", [{}])[0].get("MacAddress") or \
    ":".join(["%02X" % (random.randint(0, 255) & 0xFC | 0x02)] + ["%02X" % random.randint(0, 255) for _ in range(5)])
drives = []
if with_iso == "1":
    drives.append({"Identifier": ident(), "ImageName": "nixos.iso", "ImageType": "CD",
                   "Interface": "USB", "InterfaceVersion": 1, "ReadOnly": True})
drives.append({"Identifier": ident(), "ImageName": "disk.qcow2", "ImageType": "Disk",
               "Interface": "VirtIO", "InterfaceVersion": 1, "ReadOnly": False})
cfg = {
    "Backend": "QEMU", "ConfigurationVersion": 4,
    "Information": {"Name": name, "UUID": old.get("Information", {}).get("UUID", ident()),
                    "Icon": "nixos", "IconCustom": False},
    "System": {"Architecture": "aarch64", "Target": "virt", "CPU": "default",
               "CPUFlagsAdd": [], "CPUFlagsRemove": [], "CPUCount": int(cpus),
               "ForceMulticore": False, "MemorySize": int(mem), "JITCacheSize": 0},
    "QEMU": {"AdditionalArguments": [], "BalloonDevice": False, "DebugLog": False,
             "Hypervisor": True, "PS2Controller": False, "RNGDevice": True,
             "RTCLocalTime": False, "TPMDevice": False, "TSO": False, "UEFIBoot": True},
    "Input": {"MaximumUsbShare": 3, "UsbBusSupport": "3.0", "UsbSharing": False},
    "Sharing": {"ClipboardSharing": True, "DirectoryShareMode": "None",
                "DirectoryShareReadOnly": False},
    "Display": [{"Hardware": "virtio-gpu-gl-pci", "DynamicResolution": True,
                 "NativeResolution": False, "UpscalingFilter": "Linear",
                 "DownscalingFilter": "Linear"}],
    "Drive": drives,
    "Network": [{"Mode": "Emulated", "Hardware": "virtio-net-pci", "MacAddress": mac,
                 "IsolateFromHost": False,
                 "PortForward": [{"Protocol": "TCP", "HostAddress": "127.0.0.1",
                                  "HostPort": int(ssh_port), "GuestPort": 22}]}],
    "Serial": [{"Mode": "TcpServer", "Target": "Auto", "TcpPort": int(serial_port),
                "WaitForConnection": False, "RemoteConnectionAllowed": False}],
    "Sound": [{"Hardware": "intel-hda"}],
}
plistlib.dump(cfg, open(path, "wb"))
PY
}

# UTM keeps a VM's config in memory, so quit it before editing config.plist
quit_utm() {
    local pid
    pid=$(pgrep -x UTM || true)
    [[ -n $pid ]] || return 0
    kill "$pid"
    while kill -0 "$pid" 2>/dev/null; do sleep 1; done
}

# -----------------------------------------------------------------------------
# Serial console automation: log in on the ISO and run vm-install.sh
# -----------------------------------------------------------------------------
serial_install() { # $1 = command to type
    python3 - "$SERIAL_PORT" "$1" "$CACHE/install.log" <<'PY'
import re, socket, sys, time
port, cmd, logpath = int(sys.argv[1]), sys.argv[2], sys.argv[3]
log = open(logpath, "wb")
s = None
for _ in range(300):
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=2); break
    except OSError:
        time.sleep(1)
if s is None:
    sys.exit("cannot connect to the serial console")
s.settimeout(1)
buf, sent, last_poke, start = b"", False, 0, time.time()
ansi = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
while True:
    try:
        data = s.recv(65536)
        if not data:
            sys.exit(0 if b"VM-INSTALL-DONE" in buf else "the VM closed the serial console")
    except socket.timeout:
        data = b""
    if data:
        buf = (buf + data)[-20000:]
        log.write(data); log.flush()
        sys.stdout.buffer.write(data); sys.stdout.buffer.flush()
    tail = ansi.sub(b"", buf[-300:])
    if not sent:
        if re.search(rb"nixos@nixos[^\n]*\$ ?$", tail):
            s.sendall(cmd.encode() + b"\r"); sent = True
        elif time.time() - last_poke > 5:   # wake the getty / prompt
            s.sendall(b"\r"); last_poke = time.time()
        if time.time() - start > 900:
            sys.exit("the installer ISO never showed a shell prompt on the serial console")
    else:
        if b"VM-INSTALL-DONE" in buf:
            sys.exit(0)
        if b"VM-INSTALL-FAILED" in buf:
            sys.exit("vm-install.sh failed (log: " + logpath + ")")
        if b"reboot: Restarting system" in buf or b"reboot: Power down" in buf:
            sys.exit("the VM rebooted or powered off during the install (retry: vm.sh install --retry)")
PY
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------
cmd_install() {
    local retry=0
    if [[ ${1:-} == --retry ]]; then
        [[ -f $BUNDLE/Data/nixos.iso ]] && vm_running ||
            die "--retry needs the installer ISO still running (else: $0 install --force)"
        retry=1
    elif [[ -d $BUNDLE ]]; then
        [[ ${1:-} == --force ]] || die "$BUNDLE exists (use: $0 install --force, or $0 destroy)"
        cmd_destroy
    fi
    ensure_tools
    local key
    key=$(ssh_key)
    vm_password
    mkdir -p "$CACHE" "$BUNDLE/Data"

    if ((retry)); then
        :
    elif [[ ! -f $ISO ]]; then
        info "Downloading $(basename "$ISO_URL")"
        curl -fL --progress-bar -o "$ISO.part" "$ISO_URL"
        mv "$ISO.part" "$ISO"
    fi
    if ((!retry)); then
        info "Creating $BUNDLE (${VM_CPUS} CPUs, ${VM_MEMORY_MB} MB, ${VM_DISK_GB} GB)"
        cp -c "$ISO" "$BUNDLE/Data/nixos.iso" 2>/dev/null || cp "$ISO" "$BUNDLE/Data/nixos.iso"
        qemu-img create -q -f qcow2 "$BUNDLE/Data/disk.qcow2" "${VM_DISK_GB}G"
        write_config 1
    fi

    # The ISO fetches nixos/ (this checkout) from the Mac: QEMU's user network
    # maps 10.0.2.2 to the Mac's localhost
    local stage="$CACHE/serve"
    rm -rf "$stage" && mkdir -p "$stage"
    COPYFILE_DISABLE=1 tar --no-xattrs -C "$DOTFILES" -cf "$stage/nixos.tar" nixos
    {
        printf 'VM_USER=%q\nVM_PASSWORD=%q\nVM_TIMEZONE=%q\nVM_SSH_KEY=%q\n' \
            "$VM_USER" "$VM_PASSWORD" "$VM_TIMEZONE" "$key"
    } >"$stage/vm.env"
    python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$stage" >/dev/null 2>&1 &
    HTTP_PID=$!
    # vm.env holds the password: stop serving it and delete it however we exit
    # (pkill -P: also the serial-console client, which would hold the port)
    trap '[[ -n $HTTP_PID ]] && kill "$HTTP_PID" 2>/dev/null; pkill -P $$ 2>/dev/null; rm -rf "$CACHE/serve"' EXIT

    info "Booting the installer"
    vm_start
    local url="http://10.0.2.2:$HTTP_PORT"
    local guest="for i in \$(seq 60); do curl -fsS $url/nixos.tar -o /tmp/n.tar && break; sleep 2; done;"
    guest+=" curl -fsS $url/vm.env -o /tmp/vm.env && tar -xf /tmp/n.tar -C /tmp &&"
    guest+=" sudo bash -c 'set -a; . /tmp/vm.env; set +a; bash /tmp/nixos/vm-install.sh' || echo VM-INSTALL-\"FAILED\""
    info "Installing over the serial console (log: $CACHE/install.log)"
    serial_install "$guest"
    kill "$HTTP_PID" 2>/dev/null || true
    HTTP_PID=""
    trap - EXIT
    rm -rf "$stage"

    info "Installed; removing the ISO"
    local i
    for ((i = 0; i < 120; i++)); do
        vm_running || break
        sleep 1
    done
    quit_utm
    write_config 0
    rm -f "$BUNDLE/Data/nixos.iso"

    vm_start
    wait_for_ssh
    cmd_rebuild
    info "Done. It logs in by itself: unlock Caelestia's lock screen as $VM_USER (password: security find-generic-password -s $KEYCHAIN_ITEM -w)"
}

cmd_sync() {
    info "Copying $DOTFILES into the VM (~/nodestack/dotfiles)"
    COPYFILE_DISABLE=1 tar --no-xattrs -C "$DOTFILES" --exclude .git --exclude .nixos_timezone -cf - . |
        vm_ssh 'rm -rf ~/nodestack/dotfiles.new && mkdir -p ~/nodestack/dotfiles.new &&
                tar -xf - -C ~/nodestack/dotfiles.new && rm -rf ~/nodestack/dotfiles &&
                mv ~/nodestack/dotfiles.new ~/nodestack/dotfiles'
}

cmd_rebuild() {
    vm_start
    wait_for_ssh
    cmd_sync
    info "Running nixos/init.sh in the VM"
    vm_ssh_tty "NIXOS_TIMEZONE='$VM_TIMEZONE' NIXOS_HOST=nixos-arm bash ~/nodestack/dotfiles/nixos/init.sh"
}

cmd_destroy() {
    [[ -d $BUNDLE ]] || return 0
    vm_stop
    quit_utm
    rm -rf "$BUNDLE"
    info "Deleted $BUNDLE (remove the leftover entry from UTM's sidebar if shown)"
}

case "${1:-help}" in
install) cmd_install "${2:-}" ;;
rebuild) cmd_rebuild ;;
sync) wait_for_ssh && cmd_sync ;;
start) vm_start && info "Running (SSH: $0 ssh)" ;;
stop) vm_stop ;;
status) if vm_running; then echo running; else echo stopped; fi ;;
ssh) shift && vm_ssh_tty "$@" ;;
console) exec nc 127.0.0.1 "$SERIAL_PORT" ;;
destroy) cmd_destroy ;;
*) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
