# Changelog

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
