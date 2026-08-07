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
if [[ "$recorded_bootloader" == limine && -f /etc/default/limine ]]; then
    printf 'Limine persistence:   %s\n' "$(limine_default_contains_parameter /etc/default/limine && printf 'configured' || printf 'not configured')"
elif [[ "$recorded_bootloader" == systemd-boot ]] && systemd_boot_manager_backend_available; then
    printf 'systemd-boot persistence: %s\n' "$(systemd_boot_manager_contains_parameter /etc/sdboot-manage.conf && printf 'configured' || printf 'not configured')"
fi
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
if [[ "$recorded_bootloader" == limine && -f /etc/default/limine ]] &&
   kernel_parameter_active && ! limine_default_contains_parameter /etc/default/limine; then
    warn "$KERNEL_PARAMETER is active but missing from persistent Limine configuration."
    warn "Re-run install.sh to make it survive Limine/kernel regeneration."
    printf '\n'
elif [[ "$recorded_bootloader" == systemd-boot ]] &&
     systemd_boot_manager_backend_available &&
     kernel_parameter_active &&
     ! systemd_boot_manager_contains_parameter /etc/sdboot-manage.conf; then
    warn "$KERNEL_PARAMETER is active but missing from persistent systemd-boot-manager configuration."
    warn "Re-run install.sh to make it survive sdboot-manage/kernel regeneration."
    printf '\n'
fi
if [[ "$configured" != "not configured" &&
      "$active" == "$configured" &&
      "$service_enabled" == enabled ]]; then
    ok "The configured governor is active."
    exit 0
fi

warn "The configured governor is not fully active."
exit 1
