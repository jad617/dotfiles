# shellcheck shell=bash
# =============================================================================
# Sourced by install-from-linux.sh: runs the install itself (steps 1-7, after the
# questions and the confirmation) as a background service, so the terminal can be
# closed, and shows its progress.
#
#   bg_can_detach        a terminal, systemd, and NIXOS_INSTALL_FOREGROUND unset
#   bg_launch            writes the plan, starts the service, then bg_watch
#   bg_watch LOG         the progress view (q / Esc / closing the terminal: the install goes on)
#   bg_status            bg_watch on the running (or last) install
#   bg_running           the service is running
#
# The service is "nixos-install" (systemd-run, as root): it runs this installer again with
# --run-plan PLAN, where PLAN (/run/nixos-install/plan.env, root only, in RAM) holds the
# answers to the questions, the passwords included. The installer reads it and deletes it
# before doing anything. Its output goes to ~/nixos-install-<date>.log; "@@STEP" lines in it
# mark the steps (for the view), "@@END <code> <time>" the end.
# =============================================================================

BG_UNIT=nixos-install
BG_DIR=/run/nixos-install
# Answers and plan, as the install steps read them (USER_HOME / USER_IDS: whose home the
# log and the partition table backup go to; the service runs as root)
BG_VARS=(MODE DISK DELETE_PARTS SHRINK_PART SHRINK_GIB NIXOS_GIB BOOT_PART ROOT_PART BOOT_DEV ROOT_DEV
    RELEASE NEED_GPT FREE_START FREE_END HOST host_system USERNAME TIMEZONE PASSWORD ENCRYPT LUKS_PASS
    WIFI_UUIDS WIFI_NAMES WIFI_NOTE SSH_ITEMS SSH_SRC SSH_NOTE STALE_UUIDS lines LIVE OS_REASON
    SH_SIZE SH_USED SH_MIN GUIDED CONFIRM)

bg_running() { systemctl is-active --quiet "$BG_UNIT.service" 2>/dev/null; }
bg_can_detach() {
    [[ -t 1 && -z ${NIXOS_INSTALL_FOREGROUND:-} && -d /run/systemd/system ]] && command -v systemd-run >/dev/null
}
bg_pointer() { echo "${XDG_CACHE_HOME:-$HOME/.cache}/nixos-install/last-log"; } # holds the last log's path
bg_last_log() { local p && p=$(bg_pointer) && [[ -f $p ]] && cat "$p"; return 0; }

bg_launch() {
    local log plan v out env=()
    log=$HOME/nixos-install-$(date +%Y%m%d-%H%M%S).log
    plan=$BG_DIR/plan.env
    : >"$log" # yours: the service appends to it
    mkdir -p "$(dirname "$(bg_pointer)")" && echo "$log" >"$(bg_pointer)"
    sudo install -d -m 700 "$BG_DIR"
    {
        for v in "${BG_VARS[@]}"; do declare -p "$v" 2>/dev/null || true; done
        printf 'USER_HOME=%q\nUSER_IDS=%q\n' "$HOME" "$(id -u):$(id -g)"
    } | sudo sh -c 'umask 077 && cat >"$1"' _ "$plan"
    # the test hooks and the mount point carry over; the passwords only go through the plan
    for v in $(compgen -e | grep -E '^NIXOS_INSTALL_' || true); do env+=(--setenv="$v=${!v}"); done
    sudo systemctl reset-failed "$BG_UNIT.service" 2>/dev/null || true
    if ! out=$(sudo systemd-run --unit="$BG_UNIT" --description="NixOS install on $DISK" --service-type=exec --collect \
        --setenv=PATH="$PATH" --setenv=HOME=/root ${env[@]+"${env[@]}"} \
        -p StandardOutput=append:"$log" -p StandardError=append:"$log" \
        bash -c 'bash "$1" --run-plan "$2"; rc=$?; echo "@@END $rc $(date +%s)"; exit $rc' _ "$NIXOS_DIR/install-from-linux.sh" "$plan" 2>&1); then
        sudo rm -f "$plan"
        printf '%s\n' "$out" >&2
        die "could not start the background install (systemd-run): run it in the foreground with NIXOS_INSTALL_FOREGROUND=1"
    fi
    bg_watch "$log"
}

bg_status() {
    local log
    log=$(bg_last_log)
    if [[ -z $log || ! -f $log ]]; then
        bg_running && die "an install is running, but its log is not known here: journalctl -fu $BG_UNIT"
        echo "No install started from here (no $(bg_pointer))." && return 0
    fi
    bg_watch "$log"
}

fmt_dur() { # SECONDS -> "1h 02m" / "12m 03s" / "45s"
    local s=$1
    if ((s >= 3600)); then printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
    elif ((s >= 60)); then printf '%dm %02ds' $((s / 60)) $((s % 60))
    else printf '%ds' "$s"; fi
}
bar() { # DONE TOTAL WIDTH -> [■■■■······]
    local d=$1 t=$2 w=$3 f p
    ((t > 0)) || t=1
    ((d > t)) && d=$t
    f=$((d * w / t))
    printf -v p '%*s' "$f" '' && p=${p// /■}
    printf '%s' "$p" && printf -v p '%*s' $((w - f)) '' && printf '%s' "${p// /·}"
}

count() { grep -c -- "$1" "$2" || true; }                                       # PATTERN FILE -> lines matching
sum_n() { { grep -oE -- "$1" "$2" || true; } | awk '{ s += $2 } END { print s + 0 }'; } # "these N ..." -> sum of N

# bg_progress LOG -> sets BG_STEP BG_TOTAL BG_TITLE BG_T0 BG_TSTEP BG_BUILT BG_BUILDS BG_GOT BG_GETS
# BG_END (the exit code, once finished) BG_TEND (when it finished)
bg_progress() {
    local log=$1 l a b
    l=$({ grep '^@@STEP ' "$log" || true; } | tail -1)
    read -r _ BG_STEP BG_TOTAL BG_TSTEP BG_TITLE <<<"${l:-@@STEP 0 7 $(date +%s) starting}"
    BG_T0=$({ grep -m1 '^@@STEP ' "$log" || true; } | awk '{ print $4 }')
    BG_T0=${BG_T0:-$BG_TSTEP}
    a=$(count '^this derivation will be built' "$log") b=$(sum_n '^these [0-9]+ derivations will be built' "$log")
    BG_BUILDS=$((a + b))
    BG_BUILT=$(count "^building '/nix/store/" "$log")
    a=$(count '^this path will be fetched' "$log") b=$(sum_n '^these [0-9]+ paths will be fetched' "$log")
    BG_GETS=$((a + b))
    BG_GOT=$(count "^copying path '" "$log")
    l=$({ sed -n 's/^@@END //p' "$log" || true; } | tail -1)
    BG_END=${l%% *} BG_TEND=""
    [[ $l == *" "* ]] && BG_TEND=${l#* }
    return 0
}

bg_watch() {
    local log=$1 now text rows key frame tailn last_lines=0 n line
    [[ -f $log ]] || die "no log at $log"
    if [[ $UI != tui ]]; then # plain output: follow the log until the end
        echo "The install runs in the background: you can close this terminal. Log: $log"
        while true; do
            n=$(wc -l <"$log")
            ((n > last_lines)) && { sed -n "$((last_lines + 1)),${n}p" "$log" | grep -v '^@@' || true; }
            last_lines=$n
            bg_progress "$log"
            [[ -n $BG_END ]] && break
            bg_running || { BG_END=1 && break; }
            sleep 1
        done
    else
        # q / Esc / Ctrl-C: clear the view, say how to get back to it (the install goes on)
        trap 'printf "\033[?25h\033[H\033[2J" >/dev/tty; printf "The install goes on in the background. Back to its progress:\n  bash %s/install-from-linux.sh --status\n" "${NIXOS_DIR/#$HOME/\~}"; exit 0' INT
        # shellcheck disable=SC2034 # read by paint() / die() in install-from-linux.sh
        IN_VIEW=1 TUI_SHOWN="" # the progress view is not the menus: an error here is not "nothing changed"
        printf '\033[?25l' >/dev/tty
        while true; do
            card_width # CARD_W, for cutting the log lines below
            bg_progress "$log"
            now=$(date +%s)
            [[ -z $BG_END ]] && ! bg_running && BG_END=gone
            # shellcheck disable=SC2034 # read by screen() in install-from-linux.sh
            CRUMBS=("installing in the background")
            text="Step $BG_STEP/$BG_TOTAL   $BG_TITLE"$'\n'"Elapsed   $(fmt_dur $((now - BG_T0)))  (this step: $(fmt_dur $((now - BG_TSTEP))))"
            if ((BG_BUILDS + BG_GETS > 0)); then
                text+=$'\n\n'"Builds    $(bar "$BG_BUILT" "$BG_BUILDS" 30)  $BG_BUILT / $BG_BUILDS"
                text+=$'\n'"Downloads $(bar "$BG_GOT" "$BG_GETS" 30)  $BG_GOT / $BG_GETS"
            fi
            tailn=$((${LINES:-$(tput lines 2>/dev/null || echo 40)} - 22))
            ((tailn < 4)) && tailn=4
            rows=$({ grep -v '^@@' "$log" || true; } | tail -n "$tailn" | sed 's/\x1b\[[0-9;]*m//g')
            frame=$(
                screen "Installing NixOS" "$text"
                card_top "$DIM" "Log  ${log/#$HOME/\~}"
                # cut to the card's width (characters, not bytes: the log has box-drawing lines)
                while IFS= read -r line || [[ -n $line ]]; do card_row "$DIM" "${line:0:$((CARD_W - 4))}" "$DIM"; done <<<"${rows:- }"
                card_bottom "$DIM"
            )
            paint "$frame
   ${DIM}You can close this terminal: the install goes on. q leaves this view; back to it:
   bash ${NIXOS_DIR/#$HOME/\~}/install-from-linux.sh --status$R"
            [[ -n $BG_END ]] && break
            key=""
            IFS= read -rsn1 -t 1 key </dev/tty || true
            [[ $key == q || $key == $'\033' ]] && kill -INT $$
        done
        printf '\033[?25h' >/dev/tty
        trap - INT
        clear
    fi
    # the end: the final box (or the error) from the log
    if [[ $BG_END == 0 ]]; then
        sed -n '/╭─ .*NixOS is installed on/,$p' "$log" | grep -v '^@@' || true
        echo
        info "Done in $(fmt_dur $((${BG_TEND:-$(date +%s)} - BG_T0))). Log: $log"
        return 0
    fi
    { grep -v '^@@' "$log" || true; } | tail -n 25
    echo
    if [[ $BG_END == gone ]]; then
        printf '%serror:%s the background install stopped without finishing (killed, or the machine slept?). Log: %s\n' "$RED" "$R" "$log" >&2
    else
        printf '%serror:%s the install failed at step %s/%s (%s). Log: %s\n' "$RED" "$R" "$BG_STEP" "$BG_TOTAL" "$BG_TITLE" "$log" >&2
    fi
    return 1
}
