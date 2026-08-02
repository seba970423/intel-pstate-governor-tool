#!/usr/bin/env bash

detect_bootloader() {
    if [[ -f /etc/default/grub ]] && (
        command -v grub-mkconfig >/dev/null 2>&1 ||
        command -v grub2-mkconfig >/dev/null 2>&1 ||
        command -v update-grub >/dev/null 2>&1
    ); then
        printf 'grub\n'
        return
    fi

    local limine
    limine=$(find_limine_config 2>/dev/null || true)
    if [[ -n "$limine" ]]; then
        printf 'limine\n'
        return
    fi

    if command -v bootctl >/dev/null 2>&1 && bootctl is-installed >/dev/null 2>&1; then
        if find_systemd_boot_entries | grep -q .; then
            printf 'systemd-boot\n'
            return
        fi
    fi

    printf 'unknown\n'
}

find_limine_config() {
    local candidates=(
        /boot/limine.conf
        /boot/limine/limine.conf
        /boot/EFI/limine/limine.conf
        /efi/limine.conf
        /efi/EFI/limine/limine.conf
    )
    local file
    for file in "${candidates[@]}"; do
        [[ -f "$file" ]] && { printf '%s\n' "$file"; return 0; }
    done
    return 1
}

find_systemd_boot_entries() {
    local directory file
    for directory in /boot/loader/entries /efi/loader/entries /boot/efi/loader/entries; do
        [[ -d "$directory" ]] || continue
        for file in "$directory"/*.conf; do
            [[ -f "$file" ]] || continue
            grep -Eq '^[[:space:]]*(linux|efi)[[:space:]]+' "$file" || continue
            printf '%s\n' "$file"
        done
    done
}

grub_regenerate() {
    if command -v update-grub >/dev/null 2>&1; then
        run update-grub
        return
    fi

    local command output
    if command -v grub2-mkconfig >/dev/null 2>&1; then
        command=grub2-mkconfig
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        command=grub-mkconfig
    else
        die "No GRUB configuration generator was found."
    fi

    for output in \
        /boot/grub2/grub.cfg \
        /boot/grub/grub.cfg \
        /boot/efi/EFI/fedora/grub.cfg \
        /boot/efi/EFI/opensuse/grub.cfg; do
        if [[ -f "$output" ]]; then
            run "$command" -o "$output"
            return
        fi
    done

    die "GRUB was detected, but its generated grub.cfg location could not be determined safely."
}

grub_add_parameter() {
    local config=/etc/default/grub backup tmp
    grep -Eq '^[[:space:]]*GRUB_CMDLINE_LINUX(_DEFAULT)?=.*intel_pstate=passive' "$config" && {
        ok "$KERNEL_PARAMETER is already present in $config"
        return
    }

    backup=$(backup_file "$config" grub-default)
    state_set BOOT_CONFIG "$config"
    state_set BOOT_BACKUP "$backup"

    if (( DRY_RUN )); then
        info "Would add $KERNEL_PARAMETER to GRUB_CMDLINE_LINUX_DEFAULT in $config"
        grub_regenerate
        return
    fi

    tmp=$(mktemp)
    awk -v parameter="$KERNEL_PARAMETER" '
    BEGIN { changed=0 }
    /^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=/ && !changed {
        line=$0
        first=index(line, "\"")
        last=0
        for (i=length(line); i>=1; i--) if (substr(line,i,1)=="\"") { last=i; break }
        if (first && last>first) {
            before=substr(line,1,last-1)
            after=substr(line,last)
            if (before !~ /[[:space:]]$/ && substr(before,length(before),1)!="\"") before=before " "
            print before parameter after
            changed=1
            next
        }
    }
    { print }
    END {
        if (!changed) print "GRUB_CMDLINE_LINUX_DEFAULT=\"" parameter "\""
    }' "$config" > "$tmp"
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"
    grub_regenerate
}

grub_remove_parameter() {
    local config="${1:-/etc/default/grub}" tmp
    [[ -f "$config" ]] || { warn "GRUB config no longer exists: $config"; return; }

    if (( DRY_RUN )); then
        info "Would remove $KERNEL_PARAMETER from $config and regenerate GRUB"
        return
    fi

    tmp=$(mktemp)
    python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PY'
import re, sys
src, dst, token = sys.argv[1:]
pattern = re.compile(r'^(\s*GRUB_CMDLINE_LINUX(?:_DEFAULT)?\s*=\s*)(["\x27])(.*)\2(\s*)$')
with open(src, encoding="utf-8") as f, open(dst, "w", encoding="utf-8") as out:
    for line in f:
        raw = line.rstrip("\n")
        m = pattern.match(raw)
        if m:
            words = m.group(3).split()
            words = [w for w in words if w != token]
            raw = f"{m.group(1)}{m.group(2)}{' '.join(words)}{m.group(2)}{m.group(4)}"
        out.write(raw + "\n")
PY
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"
    grub_regenerate
}

limine_add_parameter() {
    local config backup tmp
    config=$(find_limine_config) || die "Limine configuration was not found."
    grep -Eq "^[[:space:]]*(cmdline|kernel_cmdline):.*(^|[[:space:]])${KERNEL_PARAMETER}([[:space:]]|$)" "$config" && {
        ok "$KERNEL_PARAMETER is already present in $config"
        return
    }

    backup=$(backup_file "$config" limine)
    state_set BOOT_CONFIG "$config"
    state_set BOOT_BACKUP "$backup"

    if (( DRY_RUN )); then
        info "Would append $KERNEL_PARAMETER to every Linux entry cmdline in $config"
        return
    fi

    tmp=$(mktemp)
    awk -v parameter="$KERNEL_PARAMETER" '
    /^[[:space:]]*(cmdline|kernel_cmdline):/ {
        if ($0 !~ "(^|[[:space:]])" parameter "([[:space:]]|$)") $0=$0 " " parameter
    }
    { print }' "$config" > "$tmp"

    if ! grep -Eq '^[[:space:]]*(cmdline|kernel_cmdline):' "$tmp"; then
        rm -f "$tmp"
        die "No Limine cmdline/kernel_cmdline directives were found; no changes made."
    fi
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"
}

limine_remove_parameter() {
    local config="$1" tmp
    [[ -f "$config" ]] || { warn "Limine config no longer exists: $config"; return; }
    if (( DRY_RUN )); then
        info "Would remove $KERNEL_PARAMETER from $config"
        return
    fi
    tmp=$(mktemp)
    awk -v token="$KERNEL_PARAMETER" '
    /^[[:space:]]*(cmdline|kernel_cmdline):/ {
        out=""
        for (i=1; i<=NF; i++) if ($i != token) out=out (out ? OFS : "") $i
        print out
        next
    }
    { print }' "$config" > "$tmp"
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"
}

systemd_boot_add_parameter() {
    local entry backup list=""
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        if grep -Eq "^[[:space:]]*options([[:space:]].*)?(^|[[:space:]])${KERNEL_PARAMETER}([[:space:]]|$)" "$entry"; then
            continue
        fi
        backup=$(backup_file "$entry" "systemd-boot-$(basename "$entry")")
        list+="${entry}|${backup}"$'\n'
        if (( DRY_RUN )); then
            info "Would add $KERNEL_PARAMETER to $entry"
            continue
        fi
        if grep -Eq '^[[:space:]]*options([[:space:]]|$)' "$entry"; then
            sed -Ei "/^[[:space:]]*options([[:space:]]|$)/ s|$| ${KERNEL_PARAMETER}|" "$entry"
        else
            printf 'options %s\n' "$KERNEL_PARAMETER" >> "$entry"
        fi
    done < <(find_systemd_boot_entries)

    [[ -n "$list" ]] || {
        ok "All detected systemd-boot entries already contain $KERNEL_PARAMETER"
        return
    }
    state_set BOOT_CONFIG_LIST "$list"
}

systemd_boot_remove_parameter() {
    local list="$1" line entry tmp
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        entry="${line%%|*}"
        [[ -f "$entry" ]] || { warn "Entry no longer exists: $entry"; continue; }
        if (( DRY_RUN )); then
            info "Would remove $KERNEL_PARAMETER from $entry"
            continue
        fi
        tmp=$(mktemp)
        awk -v token="$KERNEL_PARAMETER" '
        /^[[:space:]]*options([[:space:]]|$)/ {
            out=""
            for (i=1; i<=NF; i++) if ($i != token) out=out (out ? OFS : "") $i
            print out
            next
        }
        { print }' "$entry" > "$tmp"
        install -m 0644 "$tmp" "$entry"
        rm -f "$tmp"
    done <<< "$list"
}

add_kernel_parameter() {
    local bootloader="$1"
    case "$bootloader" in
        grub) grub_add_parameter ;;
        limine) limine_add_parameter ;;
        systemd-boot) systemd_boot_add_parameter ;;
        *) die "Unsupported or undetected bootloader. Add $KERNEL_PARAMETER manually." ;;
    esac
}

remove_kernel_parameter() {
    local bootloader="$1"
    case "$bootloader" in
        grub) grub_remove_parameter "$(state_get BOOT_CONFIG || printf /etc/default/grub)" ;;
        limine) limine_remove_parameter "$(state_get BOOT_CONFIG)" ;;
        systemd-boot) systemd_boot_remove_parameter "$(state_get BOOT_CONFIG_LIST)" ;;
        *) warn "No supported recorded bootloader; kernel parameter was not modified." ;;
    esac
}
