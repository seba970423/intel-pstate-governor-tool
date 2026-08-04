# Changelog

## [0.3.1] - 2026-08-04

### Added
- rEFInd detection for CachyOS ESP layouts mounted at `/boot`.
- EFI-variable fallback detection through `efibootmgr` or `bootctl`.
- Verified editing and restoration of `refind_linux.conf` files.

### Preserved
- Existing systemd-boot, GRUB, and Limine detection order and handlers.

## [0.3.0] - 2026-08-04

### Fixed
- Limine installations now always record the exact `BOOT_CONFIG` path.
- Limine ownership state is set only after verified parameter insertion.
- Limine uninstall now creates a pre-uninstall backup and verifies removal.
- Installation aborts if a non-systemd-boot handler fails to record its config path.
- Prevents `BOOTLOADER=limine` state with an empty `BOOT_CONFIG`.

## [0.2.9] - 2026-08-04

### Fixed
- Transactional, verified bootloader restoration before cleanup.
- Recovery state preserved on failure.
- Direct detection of stale recorded kernel parameters.
- Verified removal for Limine, GRUB, and systemd-boot.
- Pre-uninstall backups.

## [0.2.8] - 2026-08-04

### Fixed
- Fixed systemd-boot BLS entry discovery under `set -o pipefail`.
- Collect Type #1 entry paths before testing or editing them.
- Pass the exact discovered entries into the editing helper.
- Verify the exact parameter in every edited `options` line.
- Avoid an unnecessary image rebuild when only static BLS entries changed.

## [0.2.7] - 2026-08-04

### Fixed
- Update static systemd-boot BLS Type #1 entry `options` lines as well as `/etc/kernel/cmdline`.
- Verify `intel_pstate=passive` was written to every detected BLS entry before continuing.
- Record and reverse both systemd-boot configuration targets during uninstall.
- Avoid relying on `mkinitcpio -P` to rewrite static loader entry options.

## [0.2.6] - 2026-08-04

### Fixed
- Detect the currently running systemd-boot loader through `bootctl status`.
- Support CachyOS/systemd-boot installations that store parameters in `/etc/kernel/cmdline`.
- Rebuild systemd-boot kernel images or entries after command-line changes.
- Record whether the project actually added the parameter, avoiding removal of a pre-existing value.
- Updated repository URLs to `intel-pstate-governor-tool`.

## [0.2.5] - 2026-08-02

### Fixed
- The uninstaller now actually displays the optional reboot prompt after removing the kernel parameter.
- Removed the leftover placeholder from the failed v0.2.4 patch.
- `--yes` no longer authorizes an automatic reboot; reboot requires an explicit `y` or `yes`.

## [0.2.4] - 2026-08-02

### Added
- Optional reboot prompt after uninstall when the installer removed the kernel parameter.
- "No reboot is required" message when nothing requiring reboot changed.

## [0.2.3] - 2026-08-02

### Added
- Optional reboot prompt after installation when a reboot is actually required.
- Clear message when no reboot is required.

## [0.2.2] - 2026-08-02

### Changed
- Removed live bootloader detection from `status.sh`.
- Renamed the status field to `Recorded bootloader`.
- Renamed `Active governor(s)` to `Active governor`.
- Aligned status labels for easier scanning.

## [0.2.1] - 2026-08-02

### Fixed
- `status.sh` now uses the bootloader recorded during installation as its authoritative value.
- The generated state file is mode `0644`, allowing non-root status checks to read non-sensitive installation state.
- Status output now shows live bootloader detection separately when it differs from recorded state.
- Replaced the GitHub `OWNER` placeholder with `seba970423`.

### Changed
- Governor conflict warnings now explain that detected services may override the selected governor.

## [0.2.0] - 2026-08-02

### Added
- Interactive numbered governor menu before installation.
- `--governor NAME` command-line selection.
- Governor validation across every CPUFreq policy.
- Persistent `/etc/intel-pstate-governor.conf`.
- Generic systemd helper that reads the selected governor.
- Configured-versus-active governor status output.

### Changed
- Renamed project from `intel-pstate-ondemand` to `intel-pstate-governor`.
- Renamed service to `intel-pstate-governor.service`.
- Generalized all user-facing text away from hardcoded `ondemand`.
