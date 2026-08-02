#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/bootloaders.sh"

REMOVE_PARAMETER=ask

usage() {
    cat <<EOF
Usage: sudo ./uninstall.sh [OPTIONS]

Options:
  --dry-run               Show planned changes without modifying the system
  --yes                   Accept confirmation prompts
  --keep-kernel-parameter Do not remove intel_pstate=passive
  --remove-kernel-parameter Remove it without prompting
  --purge-state           Remove backups, state, and log after uninstalling
  -h, --help              Show this help
EOF
}

PURGE_STATE=0
while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --keep-kernel-parameter) REMOVE_PARAMETER=no ;;
        --remove-kernel-parameter) REMOVE_PARAMETER=yes ;;
        --purge-state) PURGE_STATE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

require_root
require_systemd

recorded_bootloader=$(state_get BOOTLOADER 2>/dev/null || true)
parameter_added=$(state_get PARAMETER_ADDED 2>/dev/null || printf 0)

if [[ "$REMOVE_PARAMETER" == ask ]]; then
    if [[ "$parameter_added" == 1 ]]; then
        if confirm "Remove the $KERNEL_PARAMETER kernel parameter added by this project?"; then
            REMOVE_PARAMETER=yes
        else
            REMOVE_PARAMETER=no
        fi
    else
        REMOVE_PARAMETER=no
    fi
fi

printf '%sPlanned actions%s\n' "$C_BOLD" "$C_RESET"
printf '  - Disable and remove %s\n' "$SERVICE_NAME"
printf '  - Remove %s and %s\n' "$HELPER_FILE" "$CONFIG_FILE"
[[ "$REMOVE_PARAMETER" == yes ]] && printf '  - Remove %s using recorded %s state\n' "$KERNEL_PARAMETER" "${recorded_bootloader:-unknown}"
(( PURGE_STATE )) && printf '  - Purge project state, backups, and log\n'
printf '\n'
confirm "Proceed with uninstall?" || die "Cancelled."

run systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
run rm -f "$SERVICE_FILE"
run rm -f "$HELPER_FILE"
run rm -f "$CONFIG_FILE"
run rmdir "$(dirname "$HELPER_FILE")" 2>/dev/null || true
run systemctl daemon-reload

if [[ "$REMOVE_PARAMETER" == yes ]]; then
    [[ -n "$recorded_bootloader" ]] ||
        die "No recorded bootloader state exists; refusing to guess."
    remove_kernel_parameter "$recorded_bootloader"
    log "Removed $KERNEL_PARAMETER using recorded $recorded_bootloader handler"
fi

if (( PURGE_STATE )); then
    run rm -rf "$STATE_DIR"
    run rm -f "$LOG_FILE"
fi

ok "Uninstall completed."

if [[ "$REMOVE_PARAMETER" == yes ]]; then
    printf '\n'
    info "A reboot is required for the kernel parameter removal to take effect."

    # Reboot always requires an explicit answer. --yes does not authorize it.
    read -r -p "Would you like to reboot now? [y/N] " reboot_answer
    if [[ "$reboot_answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        info "Rebooting..."
        systemctl reboot
        exit 0
    fi

    info "You can reboot later."
else
    info "No reboot is required."
fi
