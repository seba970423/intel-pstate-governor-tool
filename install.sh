#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/bootloaders.sh"

ADD_PARAMETER=ask
SELECTED_GOVERNOR=""

usage() {
    cat <<EOF
Usage: sudo ./install.sh [OPTIONS]

Options:
  --dry-run               Show planned changes without modifying the system
  --yes                   Accept confirmation prompts
  --governor NAME         Select a governor non-interactively
  --no-kernel-parameter   Do not edit the bootloader
  --kernel-parameter      Add intel_pstate=passive without prompting
  --status                Display current status and exit
  -h, --help              Show this help
EOF
}

choose_governor() {
    local governors=() item choice default_index=1 i

    mapfile -t governors < <(available_governors)
    ((${#governors[@]})) || die "No governors are available on every CPUFreq policy."

    printf '\n%sAvailable governors%s\n' "$C_BOLD" "$C_RESET"
    for i in "${!governors[@]}"; do
        item="${governors[$i]}"
        if [[ "$item" == ondemand ]]; then
            default_index=$((i + 1))
        fi
        printf '  %d. %s\n' "$((i + 1))" "$item"
    done

    while true; do
        read -r -p "Select a governor [$default_index]: " choice
        choice="${choice:-$default_index}"
        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           (( choice >= 1 && choice <= ${#governors[@]} )); then
            SELECTED_GOVERNOR="${governors[$((choice - 1))]}"
            return
        fi
        warn "Enter a number from 1 to ${#governors[@]}."
    done
}

write_governor_config() {
    local temp
    if (( DRY_RUN )); then
        info "Would write GOVERNOR=$SELECTED_GOVERNOR to $CONFIG_FILE"
        return
    fi
    temp=$(mktemp)
    printf '# Managed by intel-pstate-governor\nGOVERNOR=%q\n' "$SELECTED_GOVERNOR" > "$temp"
    install -m 0644 "$temp" "$CONFIG_FILE"
    rm -f "$temp"
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --governor)
            shift
            (($#)) || die "--governor requires a name."
            SELECTED_GOVERNOR="$1"
            ;;
        --no-kernel-parameter) ADD_PARAMETER=no ;;
        --kernel-parameter) ADD_PARAMETER=yes ;;
        --status) "$SCRIPT_DIR/status.sh"; exit $? ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

require_root
require_systemd
[[ "$(uname -s)" == Linux ]] || die "Linux is required."
[[ "$(uname -m)" == x86_64 ]] || die "Only x86_64 systems are currently supported."
[[ "$(cpu_vendor)" == GenuineIntel ]] || die "This project is intended for Intel CPUs."
compgen -G '/sys/devices/system/cpu/cpufreq/policy*' >/dev/null ||
    die "No CPUFreq policy directories were found."

bootloader=$(detect_bootloader)
driver=$(current_driver)
governors=$(current_governors)
pstate_status=$(intel_pstate_status)
conflicts=$(detect_conflicts || true)

printf '\n%sIntel P-state Governor Setup%s\n' "$C_BOLD" "$C_RESET"
printf '  CPU:             %s\n' "$(cpu_model)"
printf '  Driver:          %s\n' "$driver"
printf '  Governor(s):     %s\n' "$governors"
printf '  intel_pstate:    %s\n' "$pstate_status"
printf '  Bootloader:      %s\n' "$bootloader"
printf '  Kernel argument: %s\n' "$(kernel_parameter_active && printf 'active' || printf 'not active')"

if [[ -n "$conflicts" ]]; then
    printf '\n'
    warn "Potential governor-management conflicts detected:"
    while IFS= read -r line; do printf '  - %s\n' "$line"; done <<< "$conflicts"
    warn "These services may override the selected governor."
    warn "The installer will not disable them automatically."
fi

case "$ADD_PARAMETER" in
    ask)
        if kernel_parameter_active; then
            if [[ "$bootloader" == limine ]] &&
               limine_persistent_backend_available &&
               ! limine_default_contains_parameter /etc/default/limine; then
                warn "$KERNEL_PARAMETER is active for this boot but is missing from /etc/default/limine."
                warn "A Limine/kernel update may regenerate /boot/limine.conf and remove it."
                if confirm "Make $KERNEL_PARAMETER persistent in /etc/default/limine?"; then
                    ADD_PARAMETER=yes
                else
                    ADD_PARAMETER=no
                fi
            elif [[ "$bootloader" == systemd-boot ]] &&
                 systemd_boot_manager_backend_available &&
                 ! systemd_boot_manager_contains_parameter /etc/sdboot-manage.conf; then
                warn "$KERNEL_PARAMETER is active for this boot but is missing from /etc/sdboot-manage.conf."
                warn "sdboot-manage may regenerate loader entries and remove it during kernel/system updates."
                if confirm "Make $KERNEL_PARAMETER persistent in LINUX_OPTIONS in /etc/sdboot-manage.conf?"; then
                    ADD_PARAMETER=yes
                else
                    ADD_PARAMETER=no
                fi
            else
                ADD_PARAMETER=no
            fi
        elif [[ "$bootloader" == unknown ]]; then
            warn "Bootloader editing is unavailable; add $KERNEL_PARAMETER manually if required."
            ADD_PARAMETER=no
        elif confirm "Enable passive mode by adding $KERNEL_PARAMETER?"; then
            ADD_PARAMETER=yes
        else
            ADD_PARAMETER=no
        fi
        ;;
esac

# Attempt runtime passive mode first so the menu can expose additional governors.
if [[ "$ADD_PARAMETER" == yes &&
      -w /sys/devices/system/cpu/intel_pstate/status &&
      "$(intel_pstate_status)" != passive ]]; then
    if (( DRY_RUN )); then
        info "Dry-run cannot refresh governors after a runtime passive-mode switch."
    elif printf 'passive\n' > /sys/devices/system/cpu/intel_pstate/status 2>/dev/null; then
        ok "intel_pstate switched to passive mode for this session."
    else
        warn "Could not switch passive mode at runtime; additional governors may appear after reboot."
    fi
fi

if [[ -z "$SELECTED_GOVERNOR" ]]; then
    choose_governor
elif ! governor_available "$SELECTED_GOVERNOR"; then
    die "Governor '$SELECTED_GOVERNOR' is not available on every CPUFreq policy."
fi

printf '\n%sInstallation summary%s\n' "$C_BOLD" "$C_RESET"
printf '  Bootloader:        %s\n' "$bootloader"
printf '  Kernel parameter:  %s\n' "$([[ "$ADD_PARAMETER" == yes ]] && printf 'add' || printf 'leave unchanged')"
printf '  Selected governor: %s\n' "$SELECTED_GOVERNOR"
printf '  Persistent service:%s\n' " enabled"
printf '\n'

confirm "Proceed with installation?" || die "Cancelled."

run mkdir -p "$STATE_DIR" "$BACKUP_DIR"
state_set INSTALLED_AT "$(date --iso-8601=seconds 2>/dev/null || date)"
state_set PREVIOUS_GOVERNORS "$governors"
state_set SELECTED_GOVERNOR "$SELECTED_GOVERNOR"
state_set BOOTLOADER "$bootloader"
state_set PARAMETER_ADDED 0

if [[ "$ADD_PARAMETER" == yes ]]; then
    add_kernel_parameter "$bootloader"

    if [[ "$bootloader" == "refind" ]]; then
        if [[ "$(state_get PARAMETER_ADDED 2>/dev/null || printf 0)" == 1 &&
              -z "$(state_get BOOT_CONFIG_LIST 2>/dev/null || true)" ]]; then
            die "rEFInd handler did not record its configuration files."
        fi
    elif [[ -z "$(state_get BOOT_CONFIG 2>/dev/null || true)" &&
            "$bootloader" != "systemd-boot" ]]; then
        die "Bootloader handler did not record the configuration path."
    fi

    if [[ "$(state_get PARAMETER_ADDED 2>/dev/null || printf 0)" == 1 ]]; then
        log "Added $KERNEL_PARAMETER with $bootloader handler"
    else
        log "$KERNEL_PARAMETER was already present; no ownership was recorded"
    fi
fi

write_governor_config
write_file "$HELPER_FILE" 0755 "$SCRIPT_DIR/src/apply-governor"
write_file "$SERVICE_FILE" 0644 "$SCRIPT_DIR/systemd/intel-pstate-governor.service"

run systemctl daemon-reload
run systemctl enable "$SERVICE_NAME"

if governor_available "$SELECTED_GOVERNOR"; then
    run "$HELPER_FILE"
    run systemctl start "$SERVICE_NAME"
    ok "$SELECTED_GOVERNOR was applied."
else
    warn "$SELECTED_GOVERNOR is not currently available."
    warn "It may become available after reboot if passive mode was added."
fi

log "Installation completed with governor $SELECTED_GOVERNOR"
printf '\n'
ok "Installation completed."

if [[ "$ADD_PARAMETER" == yes ]] && ! kernel_parameter_active; then
    printf '\n'
    info "A reboot is required for the kernel parameter to take effect."
    if confirm "Would you like to reboot now?"; then
        info "Rebooting..."
        # The user has already explicitly confirmed the reboot.
        # Use -i to avoid GNOME session inhibitors blocking the reboot.
        systemctl reboot -i
        exit 0
    fi
    info "You can reboot later and then run ./status.sh to verify the result."
else
    info "No reboot is required."
fi
