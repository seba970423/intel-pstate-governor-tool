#!/usr/bin/env bash

is_current_systemd_boot() {
    command -v bootctl >/dev/null 2>&1 || return 1

    # `bootctl is-installed` may fail when the ESP cannot be resolved even
    # though the current loader is systemd-boot. `bootctl status` reports the
    # loader that actually started this system, so prefer it.
    bootctl status --no-pager 2>/dev/null |
        grep -Eqi 'Product:[[:space:]]*systemd-boot'
}

detect_bootloader() {
    # Detect the loader that actually booted the system before looking for
    # configuration files belonging to other installed bootloaders.
    if is_current_systemd_boot; then
        printf 'systemd-boot\n'
        return
    fi

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

    # rEFInd is intentionally checked after GRUB and Limine so an old EFI
    # variable cannot override an already detected active bootloader.
    if refind_is_detected; then
        printf 'refind\n'
        return
    fi

    # Fallback for a systemd-boot installation that is not the current loader.
    if command -v bootctl >/dev/null 2>&1 &&
       bootctl is-installed >/dev/null 2>&1; then
        printf 'systemd-boot\n'
        return
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


find_limine_persistent_config() {
    [[ -f /etc/default/limine ]] || return 1
    printf '%s\n' /etc/default/limine
}

limine_persistent_backend_available() {
    [[ -f /etc/default/limine ]] || return 1
    command -v limine-mkinitcpio >/dev/null 2>&1 ||
        command -v limine-update >/dev/null 2>&1
}

limine_default_contains_parameter() {
    local config="${1:-/etc/default/limine}"
    [[ -r "$config" ]] || return 1
    python3 - "$config" "$KERNEL_PARAMETER" <<'PYLIMINECHECK'
import re, sys
path, token = sys.argv[1:]
pattern = re.compile(r'^\s*KERNEL_CMDLINE(?:\[[^]]+\])?\s*\+?=\s*(["\x27])(.*?)\1')
with open(path, encoding='utf-8') as f:
    for line in f:
        if line.lstrip().startswith('#'):
            continue
        m = pattern.match(line.rstrip('\n'))
        if m and token in m.group(2).split():
            raise SystemExit(0)
raise SystemExit(1)
PYLIMINECHECK
}

limine_regenerate() {
    if command -v limine-mkinitcpio >/dev/null 2>&1; then
        run limine-mkinitcpio
        return
    fi

    if command -v limine-update >/dev/null 2>&1; then
        run limine-update
        return
    fi

    die "A persistent Limine configuration was found, but neither limine-mkinitcpio nor limine-update is available."
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

systemd_boot_refresh_images() {
    if (( DRY_RUN )); then
        if command -v mkinitcpio >/dev/null 2>&1; then
            info "Would rebuild boot images with mkinitcpio -P"
        elif command -v kernel-install >/dev/null 2>&1; then
            info "Would rebuild boot entries/images with kernel-install add-all"
        elif command -v dracut >/dev/null 2>&1; then
            info "Would rebuild initramfs/UKIs with dracut --regenerate-all --force"
        else
            warn "Would update /etc/kernel/cmdline, but no supported rebuild tool was detected."
        fi
        return 0
    fi

    if command -v mkinitcpio >/dev/null 2>&1; then
        run mkinitcpio -P
        return
    fi

    if command -v kernel-install >/dev/null 2>&1 &&
       kernel-install add-all --help >/dev/null 2>&1; then
        run kernel-install add-all
        return
    fi

    if command -v dracut >/dev/null 2>&1; then
        run dracut --regenerate-all --force
        return
    fi

    warn "/etc/kernel/cmdline was updated, but no supported boot-image rebuild tool was found."
    warn "Regenerate your kernel images or boot entries manually before rebooting."
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
    state_set BOOT_CONFIG_METHOD "grub-default"

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
    state_set PARAMETER_ADDED 1
    grub_regenerate
}

grub_remove_parameter() {
    local config="${1:-/etc/default/grub}" tmp removal_backup
    [[ -f "$config" ]] || { error "GRUB config no longer exists: $config"; return 1; }
    if (( DRY_RUN )); then info "Would back up $config, remove $KERNEL_PARAMETER, verify it, and regenerate GRUB"; return 0; fi
    removal_backup=$(backup_file "$config" grub-before-uninstall)
    info "Removal backup: $removal_backup"
    tmp=$(mktemp)
    python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PYGRUB'
import re, sys
src, dst, token = sys.argv[1:]
pattern = re.compile(r'^(\s*GRUB_CMDLINE_LINUX(?:_DEFAULT)?\s*=\s*)(["\x27])(.*)\2(\s*)$')
with open(src, encoding="utf-8") as f, open(dst, "w", encoding="utf-8") as out:
    for line in f:
        raw=line.rstrip("\n"); m=pattern.match(raw)
        if m:
            words=[w for w in m.group(3).split() if w != token]
            raw=f"{m.group(1)}{m.group(2)}{' '.join(words)}{m.group(2)}{m.group(4)}"
        out.write(raw+"\n")
PYGRUB
    install -m 0644 "$tmp" "$config"; rm -f "$tmp"
    if grub_config_contains_parameter "$config"; then error "$KERNEL_PARAMETER is still present in $config"; return 1; fi
    grub_regenerate
    ok "GRUB configuration restored and verified."
}

limine_add_parameter_raw() {
    local config backup tmp

    config=$(find_limine_config) || die "Limine configuration was not found."
    state_set BOOT_CONFIG "$config"
    state_set BOOT_CONFIG_METHOD "limine-config"

    if limine_config_contains_parameter "$config"; then
        ok "$KERNEL_PARAMETER is already present in $config"
        state_set PARAMETER_ADDED 0
        return
    fi

    backup=$(backup_file "$config" limine)
    state_set BOOT_BACKUP "$backup"

    if (( DRY_RUN )); then
        info "Would append $KERNEL_PARAMETER to every Linux entry cmdline in $config"
        return
    fi

    tmp=$(mktemp)
    awk -v parameter="$KERNEL_PARAMETER" '
    /^[[:space:]]*(cmdline|kernel_cmdline):/ {
        found=0
        for (i=1; i<=NF; i++) if ($i == parameter) found=1
        if (!found) $0=$0 " " parameter
    }
    { print }' "$config" > "$tmp"

    if ! grep -Eq '^[[:space:]]*(cmdline|kernel_cmdline):' "$tmp"; then
        rm -f "$tmp"
        die "No Limine cmdline/kernel_cmdline directives were found; no changes made."
    fi

    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"

    limine_config_contains_parameter "$config" ||
        die "Failed to verify $KERNEL_PARAMETER in $config."

    state_set PARAMETER_ADDED 1
}

limine_add_parameter() {
    local config backup generated

    # CachyOS and other limine-mkinitcpio based installations regenerate
    # /boot/limine.conf from /etc/default/limine. Modify that persistent source
    # instead of the generated output so kernel/package updates cannot erase us.
    if ! limine_persistent_backend_available; then
        limine_add_parameter_raw
        return
    fi

    config=$(find_limine_persistent_config) || die "Persistent Limine configuration was not found."
    state_set BOOT_CONFIG "$config"
    state_set BOOT_CONFIG_METHOD "limine-default"

    if limine_default_contains_parameter "$config"; then
        ok "$KERNEL_PARAMETER is already present in $config"
        state_set PARAMETER_ADDED 0
        # The source may already be correct while /boot/limine.conf is stale.
        # Regenerate so the persistent setting is applied to the boot entries.
        limine_regenerate
        return
    fi

    backup=$(backup_file "$config" limine-default)
    state_set BOOT_BACKUP "$backup"

    if (( DRY_RUN )); then
        info "Would add a persistent KERNEL_CMDLINE entry for $KERNEL_PARAMETER to $config"
        limine_regenerate
        return
    fi

    # A separate += line is intentionally used rather than rewriting the
    # distro's existing KERNEL_CMDLINE value. This minimizes the edit and is
    # valid shell-array syntax used by CachyOS' Limine tooling.
    printf '\n# Added by intel-pstate-governor\nKERNEL_CMDLINE[default]+=" %s"\n' \
        "$KERNEL_PARAMETER" >> "$config"

    limine_default_contains_parameter "$config" ||
        die "Failed to verify $KERNEL_PARAMETER in $config."

    limine_regenerate

    generated=$(find_limine_config 2>/dev/null || true)
    if [[ -n "$generated" ]] && ! limine_config_contains_parameter "$generated"; then
        die "$KERNEL_PARAMETER was saved persistently but was not found in the regenerated Limine configuration."
    fi

    state_set PARAMETER_ADDED 1
}

limine_remove_parameter_raw() {
    local config="$1" tmp removal_backup

    [[ -n "$config" ]] || { error "Recorded Limine config is missing: not recorded"; return 1; }
    [[ -f "$config" ]] || { error "Recorded Limine config does not exist: $config"; return 1; }

    if ! limine_config_contains_parameter "$config"; then
        ok "$KERNEL_PARAMETER is already absent from $config"
        return 0
    fi

    removal_backup=$(backup_file "$config" limine-pre-uninstall)
    info "Pre-uninstall backup created: $removal_backup"

    if (( DRY_RUN )); then
        info "Would remove $KERNEL_PARAMETER from $config"
        return 0
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

    if limine_config_contains_parameter "$config"; then
        error "$KERNEL_PARAMETER is still present in $config"
        return 1
    fi

    ok "Verified removal from $config"
}

limine_remove_parameter() {
    local method config tmp removal_backup generated
    method=$(state_get BOOT_CONFIG_METHOD 2>/dev/null || true)
    config=$(state_get BOOT_CONFIG 2>/dev/null || true)

    if [[ "$method" != "limine-default" ]]; then
        limine_remove_parameter_raw "$config"
        return
    fi

    [[ -n "$config" ]] || { error "Recorded persistent Limine config is missing."; return 1; }
    [[ -f "$config" ]] || { error "Recorded persistent Limine config does not exist: $config"; return 1; }

    if ! limine_default_contains_parameter "$config"; then
        ok "$KERNEL_PARAMETER is already absent from $config"
        # Regenerate anyway: a stale generated /boot/limine.conf may still
        # contain the parameter from an older version of this tool.
        limine_regenerate
        return 0
    fi

    removal_backup=$(backup_file "$config" limine-default-pre-uninstall)
    info "Pre-uninstall backup created: $removal_backup"

    if (( DRY_RUN )); then
        info "Would remove $KERNEL_PARAMETER from persistent Limine KERNEL_CMDLINE entries in $config"
        limine_regenerate
        return 0
    fi

    tmp=$(mktemp)
    python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PYLIMINEREMOVE'
import re, sys
src, dst, token = sys.argv[1:]
pattern = re.compile(r'^(\s*KERNEL_CMDLINE(?:\[[^]]+\])?\s*\+?=\s*)(["\x27])(.*?)\2(\s*(?:#.*)?)$')

out = []
with open(src, encoding='utf-8') as f:
    for line in f:
        raw = line.rstrip('\n')
        m = pattern.match(raw)
        if m and not raw.lstrip().startswith('#'):
            words = [word for word in m.group(3).split() if word != token]
            # Drop an empty line created solely by this tool. Otherwise keep
            # the user's KERNEL_CMDLINE assignment and all unrelated tokens.
            if not words and 'KERNEL_CMDLINE[default]+=' in raw:
                continue
            raw = f"{m.group(1)}{m.group(2)}{' '.join(words)}{m.group(2)}{m.group(4)}"
        if raw.strip() == '# Added by intel-pstate-governor':
            continue
        out.append(raw)

with open(dst, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out).rstrip() + '\n')
PYLIMINEREMOVE
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"

    if limine_default_contains_parameter "$config"; then
        error "$KERNEL_PARAMETER is still present in $config"
        return 1
    fi

    limine_regenerate

    generated=$(find_limine_config 2>/dev/null || true)
    if [[ -n "$generated" ]] && limine_config_contains_parameter "$generated"; then
        error "$KERNEL_PARAMETER remains in regenerated Limine configuration: $generated"
        return 1
    fi

    ok "Persistent Limine configuration restored and verified."
}

systemd_boot_manager_backend_available() {
    [[ -f /etc/sdboot-manage.conf ]] || return 1
    command -v sdboot-manage >/dev/null 2>&1
}

systemd_boot_manager_contains_parameter() {
    local config="${1:-/etc/sdboot-manage.conf}"
    [[ -r "$config" ]] || return 1
    python3 - "$config" "$KERNEL_PARAMETER" <<'PYSDCHECK'
import re, sys
path, token = sys.argv[1:]
pattern = re.compile(r'^\s*(?:export\s+)?LINUX_OPTIONS\s*=\s*(["\x27])(.*?)\1\s*(?:#.*)?$')
with open(path, encoding='utf-8') as f:
    for line in f:
        if line.lstrip().startswith('#'):
            continue
        m = pattern.match(line.rstrip('\n'))
        if m and token in m.group(2).split():
            raise SystemExit(0)
raise SystemExit(1)
PYSDCHECK
}

systemd_boot_manager_regenerate() {
    command -v sdboot-manage >/dev/null 2>&1 ||
        die "systemd-boot-manager backend selected, but sdboot-manage is unavailable."
    run sdboot-manage gen
}

systemd_boot_any_entry_contains_parameter() {
    local entry
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        systemd_boot_entry_contains_parameter "$entry" && return 0
    done < <(find_systemd_boot_entries)
    return 1
}

systemd_boot_manager_add_parameter() {
    local config=/etc/sdboot-manage.conf backup tmp

    state_set BOOT_CONFIG "$config"
    state_set BOOT_CONFIG_METHOD "sdboot-manage-conf"

    if systemd_boot_manager_contains_parameter "$config"; then
        ok "$KERNEL_PARAMETER is already present in LINUX_OPTIONS in $config"
        state_set PARAMETER_ADDED 0
        # The persistent source may already be correct while generated entries
        # are stale, so regenerate them anyway.
        systemd_boot_manager_regenerate
        return
    fi

    backup=$(backup_file "$config" systemd-boot-manager)
    state_set BOOT_BACKUP "$backup"

    if (( DRY_RUN )); then
        info "Would add $KERNEL_PARAMETER to LINUX_OPTIONS in $config"
        systemd_boot_manager_regenerate
        return
    fi

    tmp=$(mktemp)
    python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PYSDADD'
import re, sys
src, dst, token = sys.argv[1:]
pattern = re.compile(r'^(\s*(?:export\s+)?LINUX_OPTIONS\s*=\s*)(["\x27])(.*?)\2(\s*(?:#.*)?)$')
changed = False
out = []
with open(src, encoding='utf-8') as f:
    for line in f:
        raw = line.rstrip('\n')
        if not raw.lstrip().startswith('#'):
            m = pattern.match(raw)
            if m and not changed:
                words = m.group(3).split()
                if token not in words:
                    words.append(token)
                raw = f"{m.group(1)}{m.group(2)}{' '.join(words)}{m.group(2)}{m.group(4)}"
                changed = True
        out.append(raw)
if not changed:
    out.append(f'LINUX_OPTIONS="{token}"')
with open(dst, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out).rstrip() + '\n')
PYSDADD
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"

    systemd_boot_manager_contains_parameter "$config" ||
        die "Failed to verify $KERNEL_PARAMETER in LINUX_OPTIONS in $config."

    systemd_boot_manager_regenerate

    # On Type #1 entry layouts, verify that regeneration propagated the
    # persistent option into at least one generated Linux entry.
    if [[ -n "$(find_systemd_boot_entries 2>/dev/null | head -n1)" ]] &&
       ! systemd_boot_any_entry_contains_parameter; then
        die "$KERNEL_PARAMETER was saved persistently but was not found in regenerated systemd-boot entries."
    fi

    state_set PARAMETER_ADDED 1
}

systemd_boot_manager_remove_parameter() {
    local config="${1:-/etc/sdboot-manage.conf}" tmp removal_backup

    [[ -f "$config" ]] || {
        error "Recorded systemd-boot-manager config does not exist: $config"
        return 1
    }

    if ! systemd_boot_manager_contains_parameter "$config"; then
        ok "$KERNEL_PARAMETER is already absent from LINUX_OPTIONS in $config"
        systemd_boot_manager_regenerate
        return 0
    fi

    removal_backup=$(backup_file "$config" systemd-boot-manager-before-uninstall)
    info "Removal backup: $removal_backup"

    if (( DRY_RUN )); then
        info "Would remove $KERNEL_PARAMETER from LINUX_OPTIONS in $config and regenerate entries"
        systemd_boot_manager_regenerate
        return 0
    fi

    tmp=$(mktemp)
    python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PYSDREMOVE'
import re, sys
src, dst, token = sys.argv[1:]
pattern = re.compile(r'^(\s*(?:export\s+)?LINUX_OPTIONS\s*=\s*)(["\x27])(.*?)\2(\s*(?:#.*)?)$')
out = []
with open(src, encoding='utf-8') as f:
    for line in f:
        raw = line.rstrip('\n')
        if not raw.lstrip().startswith('#'):
            m = pattern.match(raw)
            if m:
                words = [w for w in m.group(3).split() if w != token]
                raw = f"{m.group(1)}{m.group(2)}{' '.join(words)}{m.group(2)}{m.group(4)}"
        out.append(raw)
with open(dst, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out).rstrip() + '\n')
PYSDREMOVE
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"

    if systemd_boot_manager_contains_parameter "$config"; then
        error "$KERNEL_PARAMETER is still present in LINUX_OPTIONS in $config"
        return 1
    fi

    systemd_boot_manager_regenerate

    if systemd_boot_any_entry_contains_parameter; then
        error "$KERNEL_PARAMETER remains in regenerated systemd-boot entries."
        return 1
    fi

    ok "Persistent systemd-boot configuration restored and verified."
}

kernel_cmdline_contains_parameter() {
    local file="$1"
    awk '
        /^[[:space:]]*#/ { next }
        { for (i=1; i<=NF; i++) print $i }
    ' "$file" | grep -Fxq "$KERNEL_PARAMETER"
}

systemd_boot_cmdline_add_parameter() {
    local config=/etc/kernel/cmdline backup tmp

    kernel_cmdline_contains_parameter "$config" && {
        ok "$KERNEL_PARAMETER is already present in $config"
        return
    }

    backup=$(backup_file "$config" systemd-boot-kernel-cmdline)
    state_set BOOT_CONFIG "$config"
    state_set BOOT_BACKUP "$backup"
    state_set BOOT_CONFIG_METHOD "kernel-cmdline"

    if (( DRY_RUN )); then
        info "Would add $KERNEL_PARAMETER to $config"
        systemd_boot_refresh_images
        return
    fi

    tmp=$(mktemp)
    python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PY'
import sys
src, dst, token = sys.argv[1:]
with open(src, encoding="utf-8") as f:
    lines = f.read().splitlines()

changed = False
output = []
for line in lines:
    stripped = line.strip()
    if not changed and stripped and not stripped.startswith("#"):
        words = stripped.split()
        if token not in words:
            words.append(token)
        leading = line[:len(line) - len(line.lstrip())]
        output.append(leading + " ".join(words))
        changed = True
    else:
        output.append(line)

if not changed:
    output.append(token)

with open(dst, "w", encoding="utf-8") as f:
    f.write("\n".join(output) + "\n")
PY
    install -m 0644 "$tmp" "$config"
    rm -f "$tmp"
}

systemd_boot_cmdline_remove_parameter() {
    local config="$1" tmp removal_backup
    [[ -n "$config" && -f "$config" ]] || { error "Kernel command-line file no longer exists: ${config:-not recorded}"; return 1; }
    if (( DRY_RUN )); then info "Would back up $config, remove $KERNEL_PARAMETER, verify it, and rebuild boot images"; return 0; fi
    removal_backup=$(backup_file "$config" systemd-boot-cmdline-before-uninstall)
    info "Removal backup: $removal_backup"
    tmp=$(mktemp)
    python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PYCMD'
import sys
src,dst,token=sys.argv[1:]
lines=open(src,encoding='utf-8').read().splitlines(); out=[]
for line in lines:
    stripped=line.strip()
    if stripped and not stripped.startswith('#'):
        leading=line[:len(line)-len(line.lstrip())]
        out.append(leading+' '.join(w for w in stripped.split() if w != token))
    else: out.append(line)
open(dst,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PYCMD
    install -m 0644 "$tmp" "$config"; rm -f "$tmp"
    if kernel_cmdline_contains_parameter "$config"; then error "$KERNEL_PARAMETER is still present in $config"; return 1; fi
    systemd_boot_refresh_images
    ok "Kernel command-line source restored and verified."
}

systemd_boot_entries_add_parameter() {
    local entry backup list=""
    local -a target_entries=("$@")

    if ((${#target_entries[@]} == 0)); then
        mapfile -t target_entries < <(find_systemd_boot_entries)
    fi

    for entry in "${target_entries[@]}"; do
        [[ -n "$entry" ]] || continue

        if awk -v token="$KERNEL_PARAMETER" '
            /^[[:space:]]*options([[:space:]]|$)/ {
                for (i=2; i<=NF; i++) if ($i == token) found=1
            }
            END { exit(found ? 0 : 1) }
        ' "$entry"; then
            continue
        fi

        backup=$(backup_file "$entry" "systemd-boot-$(basename "$entry")")
        list+="${entry}|${backup}"$'\n'

        if (( DRY_RUN )); then
            info "Would add $KERNEL_PARAMETER to $entry"
            continue
        fi

        if grep -Eq '^[[:space:]]*options([[:space:]]|$)' "$entry"; then
            sed -Ei "/^[[:space:]]*options([[:space:]]|$)/ s|[[:space:]]*$| ${KERNEL_PARAMETER}|" "$entry"
        else
            printf 'options %s\n' "$KERNEL_PARAMETER" >> "$entry"
        fi
    done

    [[ -n "$list" ]] || {
        ok "All detected systemd-boot entries already contain $KERNEL_PARAMETER"
        return
    }

    state_set BOOT_CONFIG_LIST "$list"
}

systemd_boot_entries_remove_parameter() {
    local list="$1" line entry tmp removal_backup processed=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        entry="${line%%|*}"
        [[ -f "$entry" ]] || { error "Recorded systemd-boot entry no longer exists: $entry"; return 1; }
        processed=1
        if (( DRY_RUN )); then info "Would back up $entry, remove $KERNEL_PARAMETER, and verify removal"; continue; fi
        removal_backup=$(backup_file "$entry" "systemd-boot-$(basename "$entry")-before-uninstall")
        info "Removal backup: $removal_backup"
        tmp=$(mktemp)
        awk -v token="$KERNEL_PARAMETER" '''
        /^[[:space:]]*options([[:space:]]|$)/ {
            out=$1
            for (i=2; i<=NF; i++) if ($i != token) out=out OFS $i
            print out; next
        }
        { print }''' "$entry" > "$tmp"
        install -m 0644 "$tmp" "$entry"; rm -f "$tmp"
        if systemd_boot_entry_contains_parameter "$entry"; then error "$KERNEL_PARAMETER is still present in $entry"; return 1; fi
    done <<< "$list"
    (( processed )) || { error "No recorded systemd-boot entries were available for restoration."; return 1; }
    (( DRY_RUN )) || ok "systemd-boot entries restored and verified."
}

systemd_boot_add_parameter() {
    if systemd_boot_manager_backend_available; then
        systemd_boot_manager_add_parameter
        return
    fi

    local cmdline_changed=0
    local entries_changed=0
    local have_cmdline=0
    local before_state
    local entry missing=0
    local -a entries=()

    [[ -f /etc/kernel/cmdline ]] && have_cmdline=1

    # Do not use `find_systemd_boot_entries | grep -q .` here. With pipefail
    # enabled, grep may exit after its first match and cause the producer to
    # receive SIGPIPE, making a successful discovery look like failure.
    mapfile -t entries < <(find_systemd_boot_entries)

    if (( ! have_cmdline && ${#entries[@]} == 0 )); then
        die "systemd-boot was detected, but neither /etc/kernel/cmdline nor supported Type #1 loader entries were found."
    fi

    before_state=$(state_get PARAMETER_ADDED 2>/dev/null || printf 0)

    if (( have_cmdline )); then
        if kernel_cmdline_contains_parameter /etc/kernel/cmdline; then
            ok "$KERNEL_PARAMETER is already present in /etc/kernel/cmdline"
        else
            systemd_boot_cmdline_add_parameter
            cmdline_changed=1

            if (( ! DRY_RUN )) && ! kernel_cmdline_contains_parameter /etc/kernel/cmdline; then
                die "Failed to verify $KERNEL_PARAMETER in /etc/kernel/cmdline."
            fi
        fi
    fi

    if ((${#entries[@]})); then
        for entry in "${entries[@]}"; do
            if ! awk -v token="$KERNEL_PARAMETER" '
                /^[[:space:]]*options([[:space:]]|$)/ {
                    for (i=2; i<=NF; i++) if ($i == token) found=1
                }
                END { exit(found ? 0 : 1) }
            ' "$entry"; then
                missing=1
                break
            fi
        done

        if (( missing )); then
            systemd_boot_entries_add_parameter "${entries[@]}"
            entries_changed=1

            if (( ! DRY_RUN )); then
                for entry in "${entries[@]}"; do
                    awk -v token="$KERNEL_PARAMETER" '
                        /^[[:space:]]*options([[:space:]]|$)/ {
                            for (i=2; i<=NF; i++) if ($i == token) found=1
                        }
                        END { exit(found ? 0 : 1) }
                    ' "$entry" || die "Failed to verify $KERNEL_PARAMETER in $entry."
                done
            fi
        else
            ok "All detected systemd-boot entries already contain $KERNEL_PARAMETER"
        fi
    fi

    # /etc/kernel/cmdline is an input for generated images/entries, so rebuild
    # only when that source file itself changed. Direct edits to static Type #1
    # entries are effective without rebuilding initramfs images.
    if (( cmdline_changed )); then
        systemd_boot_refresh_images
    fi

    if (( cmdline_changed || entries_changed )); then
        state_set PARAMETER_ADDED 1

        if (( have_cmdline && ${#entries[@]} > 0 )); then
            state_set BOOT_CONFIG_METHOD "kernel-cmdline+loader-entries"
        elif (( have_cmdline )); then
            state_set BOOT_CONFIG_METHOD "kernel-cmdline"
        else
            state_set BOOT_CONFIG_METHOD "loader-entries"
        fi
    else
        state_set PARAMETER_ADDED "$before_state"
    fi
}

systemd_boot_remove_parameter() {
    local method config list
    method=$(state_get BOOT_CONFIG_METHOD 2>/dev/null || true)
    config=$(state_get BOOT_CONFIG 2>/dev/null || true)
    list=$(state_get BOOT_CONFIG_LIST 2>/dev/null || true)

    if [[ "$method" == "sdboot-manage-conf" ]]; then
        systemd_boot_manager_remove_parameter "${config:-/etc/sdboot-manage.conf}"
        return
    fi

    case "$method" in
        kernel-cmdline+loader-entries)
            [[ -n "$config" ]] || { error "No recorded /etc/kernel/cmdline target."; return 1; }
            [[ -n "$list" ]] || { error "No recorded systemd-boot entry list."; return 1; }
            systemd_boot_cmdline_remove_parameter "$config" || return 1
            systemd_boot_entries_remove_parameter "$list" || return 1 ;;
        kernel-cmdline)
            [[ -n "$config" ]] || { error "No recorded kernel command-line target."; return 1; }
            systemd_boot_cmdline_remove_parameter "$config" || return 1 ;;
        loader-entries)
            [[ -n "$list" ]] || { error "No recorded systemd-boot entry list."; return 1; }
            systemd_boot_entries_remove_parameter "$list" || return 1 ;;
        *) error "No supported recorded systemd-boot configuration method was found."; return 1 ;;
    esac
}

grub_config_contains_parameter() {
    local config="$1"
    [[ -r "$config" ]] || return 1
    python3 - "$config" "$KERNEL_PARAMETER" <<'PYVERIFY'
import re,sys
path,token=sys.argv[1:]
pat=re.compile(r'^\s*GRUB_CMDLINE_LINUX(?:_DEFAULT)?\s*=\s*(["\x27])(.*)\1\s*$')
for line in open(path,encoding='utf-8'):
    m=pat.match(line.rstrip('\n'))
    if m and token in m.group(2).split(): raise SystemExit(0)
raise SystemExit(1)
PYVERIFY
}

limine_config_contains_parameter() {
    local config="$1"; [[ -r "$config" ]] || return 1
    awk -v token="$KERNEL_PARAMETER" '''/^[[:space:]]*(cmdline|kernel_cmdline):/ {for(i=2;i<=NF;i++) if($i==token) found=1} END{exit(found?0:1)}''' "$config"
}

systemd_boot_entry_contains_parameter() {
    local entry="$1"; [[ -r "$entry" ]] || return 1
    awk -v token="$KERNEL_PARAMETER" '''/^[[:space:]]*options([[:space:]]|$)/ {for(i=2;i<=NF;i++) if($i==token) found=1} END{exit(found?0:1)}''' "$entry"
}

recorded_bootloader_parameter_present() {
    local bootloader="$1" config list line entry
    case "$bootloader" in
        grub) config=$(state_get BOOT_CONFIG 2>/dev/null || printf /etc/default/grub); grub_config_contains_parameter "$config" ;;
        limine)
            config=$(state_get BOOT_CONFIG 2>/dev/null || true)
            if [[ "$(state_get BOOT_CONFIG_METHOD 2>/dev/null || true)" == "limine-default" ]]; then
                [[ -n "$config" ]] && limine_default_contains_parameter "$config"
            else
                [[ -n "$config" ]] && limine_config_contains_parameter "$config"
            fi
            ;;
        refind)
            list=$(state_get BOOT_CONFIG_LIST 2>/dev/null || true)
            while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                entry="${line%%|*}"
                refind_has_parameter "$entry" && return 0
            done <<< "$list"
            return 1 ;;
        systemd-boot)
            config=$(state_get BOOT_CONFIG 2>/dev/null || true); list=$(state_get BOOT_CONFIG_LIST 2>/dev/null || true)
            if [[ "$(state_get BOOT_CONFIG_METHOD 2>/dev/null || true)" == "sdboot-manage-conf" ]]; then
                systemd_boot_manager_contains_parameter "${config:-/etc/sdboot-manage.conf}"
                return
            fi
            [[ -n "$config" ]] && kernel_cmdline_contains_parameter "$config" && return 0
            while IFS= read -r line; do [[ -n "$line" ]] || continue; entry="${line%%|*}"; systemd_boot_entry_contains_parameter "$entry" && return 0; done <<< "$list"
            return 1 ;;
        *) return 1 ;;
    esac
}

verify_recorded_bootloader_parameter_absent() {
    local bootloader="$1"
    if recorded_bootloader_parameter_present "$bootloader"; then error "$KERNEL_PARAMETER remains in the recorded $bootloader configuration."; return 1; fi
}


find_refind_binary() {
    local file
    for file in \
        /boot/EFI/refind/refind_x64.efi \
        /boot/efi/EFI/refind/refind_x64.efi \
        /efi/EFI/refind/refind_x64.efi; do
        [[ -f "$file" ]] && { printf '%s\n' "$file"; return 0; }
    done

    find /boot /boot/efi /efi -maxdepth 5 -type f \
        -iname refind_x64.efi -print -quit 2>/dev/null
}

refind_is_detected() {
    [[ -n "$(find_refind_binary 2>/dev/null || true)" ]] && return 0

    if command -v efibootmgr >/dev/null 2>&1 &&
       efibootmgr -v 2>/dev/null | grep -Eqi 'rEFInd|refind_x64\.efi'; then
        return 0
    fi

    if command -v bootctl >/dev/null 2>&1 &&
       bootctl status --no-pager 2>/dev/null |
           grep -Eqi 'Title:[[:space:]]*rEFInd Boot Manager|refind_x64\.efi'; then
        return 0
    fi

    return 1
}

find_refind_linux_configs() {
    local root file
    for root in /boot /boot/efi /efi; do
        [[ -d "$root" ]] || continue
        while IFS= read -r -d '' file; do
            [[ -f "$file" ]] && printf '%s\n' "$file"
        done < <(find "$root" -maxdepth 5 -type f -name refind_linux.conf -print0 2>/dev/null)
    done
}

refind_has_parameter() {
    local config="$1"
    grep -Eq '^[[:space:]]*"[^"]*"[[:space:]]+"[^"]*(^|[[:space:]])'"${KERNEL_PARAMETER}"'([[:space:]]|")' "$config"
}

refind_add_parameter() {
    local config backup tmp list=""
    local -a configs=()
    mapfile -t configs < <(find_refind_linux_configs)

    ((${#configs[@]})) ||
        die "rEFInd was detected, but no refind_linux.conf file was found."

    for config in "${configs[@]}"; do
        if refind_has_parameter "$config"; then
            ok "$KERNEL_PARAMETER is already present in $config"
            continue
        fi

        backup=$(backup_file "$config" "refind-$(basename "$(dirname "$config")")")
        list+="${config}|${backup}"$'\n'

        if (( DRY_RUN )); then
            info "Would add $KERNEL_PARAMETER to $config"
            continue
        fi

        tmp=$(mktemp)
        python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PY'
import sys
src, dst, token = sys.argv[1:]
out = []
for line in open(src, encoding="utf-8"):
    raw = line.rstrip("\n")
    stripped = raw.lstrip()
    if stripped and not stripped.startswith("#"):
        first, last = raw.find('"'), raw.rfind('"')
        if first != -1 and last > first:
            words = raw[first + 1:last].split()
            if token not in words:
                words.append(token)
            raw = raw[:first + 1] + " ".join(words) + raw[last:]
    out.append(raw)
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
        install -m 0644 "$tmp" "$config"
        rm -f "$tmp"

        refind_has_parameter "$config" ||
            die "Failed to verify $KERNEL_PARAMETER in $config."
    done

    state_set BOOT_CONFIG_METHOD "refind-linux-conf"
    if [[ -n "$list" ]]; then
        state_set BOOT_CONFIG_LIST "$list"
        state_set PARAMETER_ADDED 1
    else
        state_set PARAMETER_ADDED 0
    fi
}

refind_remove_parameter() {
    local list="$1" line config tmp backup
    [[ -n "$list" ]] || {
        error "Recorded rEFInd configuration list is missing."
        return 1
    }

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        config="${line%%|*}"

        [[ -f "$config" ]] || {
            error "Recorded rEFInd config does not exist: $config"
            return 1
        }

        if ! refind_has_parameter "$config"; then
            ok "$KERNEL_PARAMETER is already absent from $config"
            continue
        fi

        backup=$(backup_file "$config" "refind-pre-uninstall")
        info "Pre-uninstall backup created: $backup"

        if (( DRY_RUN )); then
            info "Would remove $KERNEL_PARAMETER from $config"
            continue
        fi

        tmp=$(mktemp)
        python3 - "$config" "$tmp" "$KERNEL_PARAMETER" <<'PY'
import sys
src, dst, token = sys.argv[1:]
out = []
for line in open(src, encoding="utf-8"):
    raw = line.rstrip("\n")
    stripped = raw.lstrip()
    if stripped and not stripped.startswith("#"):
        first, last = raw.find('"'), raw.rfind('"')
        if first != -1 and last > first:
            words = [w for w in raw[first + 1:last].split() if w != token]
            raw = raw[:first + 1] + " ".join(words) + raw[last:]
    out.append(raw)
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
        install -m 0644 "$tmp" "$config"
        rm -f "$tmp"

        if refind_has_parameter "$config"; then
            error "$KERNEL_PARAMETER is still present in $config"
            return 1
        fi

        ok "Verified removal from $config"
    done <<< "$list"

    return 0
}


add_kernel_parameter() {
    local bootloader="$1"
    case "$bootloader" in
        grub) grub_add_parameter ;;
        limine) limine_add_parameter ;;
        refind) refind_add_parameter ;;
        systemd-boot) systemd_boot_add_parameter ;;
        *) die "Unsupported or undetected bootloader. Add $KERNEL_PARAMETER manually." ;;
    esac
}

remove_kernel_parameter() {
    local bootloader="$1"
    case "$bootloader" in
        grub) grub_remove_parameter "$(state_get BOOT_CONFIG 2>/dev/null || printf /etc/default/grub)" ;;
        limine) limine_remove_parameter ;;
        refind) refind_remove_parameter "$(state_get BOOT_CONFIG_LIST 2>/dev/null || true)" ;;
        systemd-boot) systemd_boot_remove_parameter ;;
        *) error "Unsupported recorded bootloader: ${bootloader:-not recorded}"; return 1 ;;
    esac
}
