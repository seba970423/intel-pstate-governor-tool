#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/bootloaders.sh"
REMOVE_PARAMETER=ask; PURGE_STATE=0
usage(){ cat <<EOF
Usage: sudo ./uninstall.sh [OPTIONS]
  --dry-run
  --yes
  --keep-kernel-parameter
  --remove-kernel-parameter
  --purge-state
  -h, --help
EOF
}
while (($#)); do case "$1" in --dry-run) DRY_RUN=1;; --yes|-y) ASSUME_YES=1;; --keep-kernel-parameter) REMOVE_PARAMETER=no;; --remove-kernel-parameter) REMOVE_PARAMETER=yes;; --purge-state) PURGE_STATE=1;; -h|--help) usage; exit 0;; *) die "Unknown option: $1";; esac; shift; done
require_root; require_systemd
recorded_bootloader=$(state_get BOOTLOADER 2>/dev/null || true)
parameter_added=$(state_get PARAMETER_ADDED 2>/dev/null || printf 0)
parameter_present=0
if [[ -n "$recorded_bootloader" ]] && recorded_bootloader_parameter_present "$recorded_bootloader"; then parameter_present=1; fi
if [[ "$REMOVE_PARAMETER" == ask ]]; then
  if [[ "$parameter_added" == 1 || "$parameter_present" == 1 ]]; then
    confirm "Remove the $KERNEL_PARAMETER kernel parameter from the recorded $recorded_bootloader configuration?" && REMOVE_PARAMETER=yes || REMOVE_PARAMETER=no
  else REMOVE_PARAMETER=no; fi
fi
printf '%sPlanned actions%s
' "$C_BOLD" "$C_RESET"
[[ "$REMOVE_PARAMETER" == yes ]] && printf '  1. Restore and verify the recorded %s bootloader configuration
' "${recorded_bootloader:-unknown}"
printf '  - Disable and remove %s
' "$SERVICE_NAME"
printf '  - Remove %s and %s
' "$HELPER_FILE" "$CONFIG_FILE"
(( PURGE_STATE )) && printf '  - Purge project state, backups, and log after verification
'
printf '
'; confirm "Proceed with uninstall?" || die "Cancelled."
if [[ "$REMOVE_PARAMETER" == yes ]]; then
  [[ -n "$recorded_bootloader" ]] || die "No recorded bootloader state exists; refusing to guess."
  info "Restoring recorded $recorded_bootloader configuration..."
  if ! remove_kernel_parameter "$recorded_bootloader"; then error "Bootloader restoration failed."; error "Project state and installed files were preserved for recovery."; exit 1; fi
  if (( ! DRY_RUN )) && ! verify_recorded_bootloader_parameter_absent "$recorded_bootloader"; then error "Bootloader restoration verification failed."; error "Project state and installed files were preserved for recovery."; exit 1; fi
  ok "Bootloader restoration verification passed."
  log "Removed and verified $KERNEL_PARAMETER using recorded $recorded_bootloader state"
fi
run systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
run rm -f "$SERVICE_FILE" "$HELPER_FILE" "$CONFIG_FILE"
run rmdir "$(dirname "$HELPER_FILE")" 2>/dev/null || true
run systemctl daemon-reload
if (( PURGE_STATE )); then run rm -rf "$STATE_DIR"; run rm -f "$LOG_FILE"; else state_set PARAMETER_ADDED 0; state_set UNINSTALLED_AT "$(date --iso-8601=seconds 2>/dev/null || date)"; fi
ok "Service and installed files removed."
ok "Uninstall completed successfully."
if [[ "$REMOVE_PARAMETER" == yes ]]; then printf '
'; info "A reboot is required for the kernel parameter removal to take effect."; read -r -p "Would you like to reboot now? [y/N] " reboot_answer; if [[ "$reboot_answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then info "Rebooting..."; # The user has already explicitly confirmed the reboot.
# Use -i to avoid GNOME session inhibitors blocking the reboot.
systemctl reboot -i; exit 0; fi; info "You can reboot later."; else info "No reboot is required."; fi
