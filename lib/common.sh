#!/usr/bin/env bash

PROJECT_NAME="intel-pstate-governor"
STATE_DIR="/var/lib/${PROJECT_NAME}"
BACKUP_DIR="${STATE_DIR}/backups"
STATE_FILE="${STATE_DIR}/state"
LOG_FILE="/var/log/${PROJECT_NAME}.log"
KERNEL_PARAMETER="intel_pstate=passive"
SERVICE_NAME="intel-pstate-governor.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_FILE="/etc/intel-pstate-governor.conf"
HELPER_FILE="/usr/local/libexec/${PROJECT_NAME}/apply-governor"

DRY_RUN=0
ASSUME_YES=0

supports_color() {
    [[ -t 1 && -z "${NO_COLOR:-}" ]]
}

if supports_color; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_BLUE=$'\033[34m'
else
    C_RESET="" C_BOLD="" C_GREEN="" C_YELLOW="" C_RED="" C_BLUE=""
fi

info()  { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
error() { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { error "$*"; exit 1; }

log() {
    local message="$*"
    if (( DRY_RUN )); then
        return 0
    fi
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '%s %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)" "$message" >> "$LOG_FILE" 2>/dev/null || true
}

run() {
    if (( DRY_RUN )); then
        printf '%s[DRY ]%s' "$C_YELLOW" "$C_RESET"
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

require_root() {
    (( EUID == 0 )) || die "Run this command as root, for example: sudo $0"
}

require_systemd() {
    command -v systemctl >/dev/null 2>&1 || die "systemd/systemctl is required."
    [[ -d /run/systemd/system ]] || die "This system does not appear to be booted with systemd."
}

confirm() {
    local prompt="${1:-Continue?}"
    (( ASSUME_YES )) && return 0
    read -r -p "$prompt [y/N] " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

cpu_vendor() {
    awk -F: '/vendor_id/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' /proc/cpuinfo
}

cpu_model() {
    awk -F: '/model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' /proc/cpuinfo
}

current_driver() {
    local p
    for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_driver; do
        [[ -r "$p" ]] || continue
        cat "$p"
        return
    done
    printf 'unknown\n'
}

current_governors() {
    local p value
    declare -A seen=()
    for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
        [[ -r "$p" ]] || continue
        value=$(<"$p")
        seen["$value"]=1
    done
    if ((${#seen[@]} == 0)); then
        printf 'unknown\n'
    else
        printf '%s\n' "${!seen[@]}" | sort | paste -sd, -
    fi
}


available_governors() {
    local first=1 p governor
    declare -A common=() current=()

    for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_available_governors; do
        [[ -r "$p" ]] || continue
        current=()
        for governor in $(<"$p"); do
            current["$governor"]=1
        done

        if (( first )); then
            for governor in "${!current[@]}"; do common["$governor"]=1; done
            first=0
        else
            for governor in "${!common[@]}"; do
                [[ -n "${current[$governor]+x}" ]] || unset 'common[$governor]'
            done
        fi
    done

    (( first == 0 )) || return 1
    printf '%s\n' "${!common[@]}" | sort
}

governor_available() {
    local wanted="$1"
    available_governors | grep -Fxq "$wanted"
}

configured_governor() {
    [[ -r "$CONFIG_FILE" ]] || { printf 'not configured\n'; return; }
    local GOVERNOR=""
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    printf '%s\n' "${GOVERNOR:-not configured}"
}

ondemand_available() {
    local p
    for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_available_governors; do
        [[ -r "$p" ]] || continue
        grep -qw ondemand "$p" || return 1
    done
    compgen -G '/sys/devices/system/cpu/cpufreq/policy*/scaling_available_governors' >/dev/null
}

kernel_parameter_active() {
    grep -qw "$KERNEL_PARAMETER" /proc/cmdline
}

intel_pstate_status() {
    if [[ -r /sys/devices/system/cpu/intel_pstate/status ]]; then
        cat /sys/devices/system/cpu/intel_pstate/status
    else
        printf 'unavailable\n'
    fi
}

detect_conflicts() {
    local candidates=(
        power-profiles-daemon.service
        tuned.service
        tlp.service
        auto-cpufreq.service
        cpupower.service
    )
    local unit active enabled
    for unit in "${candidates[@]}"; do
        active=$(systemctl is-active "$unit" 2>/dev/null || true)
        enabled=$(systemctl is-enabled "$unit" 2>/dev/null || true)
        if [[ "$active" == active || "$enabled" == enabled ]]; then
            printf '%s (%s/%s)\n' "$unit" "$active" "$enabled"
        fi
    done
}

backup_file() {
    local file="$1" tag="${2:-file}" destination
    [[ -f "$file" ]] || die "Cannot back up missing file: $file"
    destination="${BACKUP_DIR}/${tag}.$(date +%Y%m%d-%H%M%S).bak"
    run mkdir -p "$BACKUP_DIR"
    run cp -a -- "$file" "$destination"
    printf '%s\n' "$destination"
}

state_set() {
    local key="$1" value="$2" tmp
    (( DRY_RUN )) && return 0
    mkdir -p "$STATE_DIR"
    touch "$STATE_FILE"
    tmp=$(mktemp)
    grep -v "^${key}=" "$STATE_FILE" > "$tmp" || true
    printf '%s=%q\n' "$key" "$value" >> "$tmp"
    install -m 0644 "$tmp" "$STATE_FILE"
    rm -f "$tmp"
}

state_get() {
    local key="$1"
    [[ -r "$STATE_FILE" ]] || return 1
    (
        # The state file is root-owned, generated by this project, and shell-escaped.
        source "$STATE_FILE"
        printf '%s\n' "${!key-}"
    )
}

write_file() {
    local destination="$1" mode="$2" source="$3"
    if (( DRY_RUN )); then
        info "Would install $destination"
        return 0
    fi
    install -D -m "$mode" "$source" "$destination"
}

remove_exact_word_from_line() {
    # stdin -> stdout; removes one exact shell-like whitespace-delimited token.
    awk -v token="$KERNEL_PARAMETER" '
    {
        out=""
        for (i=1; i<=NF; i++) {
            if ($i != token) out = out (out ? OFS : "") $i
        }
        print out
    }'
}
