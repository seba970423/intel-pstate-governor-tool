#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/bootloaders.sh"

recorded_bootloader=$(state_get BOOTLOADER 2>/dev/null || printf 'not recorded')
service_enabled=$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || printf 'not installed')
service_active=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || printf 'inactive')
configured=$(configured_governor)
active=$(current_governors)
available=$(available_governors 2>/dev/null | paste -sd' ' - || printf 'unknown')
conflicts=$(detect_conflicts 2>/dev/null || true)

printf '%sIntel P-state Governor Status%s\n\n' "$C_BOLD" "$C_RESET"
printf 'CPU:                  %s\n' "$(cpu_model)"
printf 'Vendor:               %s\n' "$(cpu_vendor)"
printf 'Scaling driver:       %s\n' "$(current_driver)"
printf 'Configured governor:  %s\n' "$configured"
printf 'Active governor:      %s\n' "$active"
printf 'Available governors:  %s\n' "$available"
printf 'intel_pstate mode:    %s\n' "$(intel_pstate_status)"
printf 'Kernel parameter:     %s\n' "$(kernel_parameter_active && printf 'active' || printf 'not active')"
printf 'Recorded bootloader:  %s\n' "$recorded_bootloader"
printf 'Service enabled:      %s\n' "$service_enabled"
printf 'Service active:       %s\n' "$service_active"

if [[ -n "$conflicts" ]]; then
    printf '\nPotential conflicts:\n'
    while IFS= read -r conflict; do
        [[ -n "$conflict" ]] || continue
        printf '  - %s\n' "$conflict"
    done <<< "$conflicts"
    printf '\nThese services may override the configured governor.\n'
fi

printf '\n'
if [[ "$configured" != "not configured" &&
      "$active" == "$configured" &&
      "$service_enabled" == enabled ]]; then
    ok "The configured governor is active."
    exit 0
fi

warn "The configured governor is not fully active."
exit 1
