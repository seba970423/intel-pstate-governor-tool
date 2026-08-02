# Intel P-state Governor

A simple, interactive utility that configures Intel CPU frequency governors on Linux systems.

Instead of manually editing your bootloader, creating systemd services and changing CPU governors after every installation, this project automates the entire process while remaining fully reversible.

---

## Features

- Interactive installer
- Automatic Intel CPU detection
- Automatic bootloader detection
    - Limine
    - GRUB
    - systemd-boot
- Optional `intel_pstate=passive` configuration
- Runtime passive-mode switch (when supported)
- Interactive governor selection
- Automatic governor persistence through systemd
- Safe uninstall
- Bootloader backup before modifications
- Dry-run mode
- Status utility
- Conflict detection (power-profiles-daemon, etc.)
- Optional reboot prompt after install
- Optional reboot prompt after uninstall

---

## Why this project?

Many Linux users manually perform the following steps after every installation:

- add `intel_pstate=passive`
- regenerate the bootloader configuration
- switch governors
- create a systemd service
- remember how to undo everything later

This utility automates the process safely while keeping every change reversible.

---

## Supported hardware

- Intel x86_64 CPUs
- Linux
- systemd

---

## Supported bootloaders

Currently supported:

- Limine
- GRUB
- systemd-boot (Type 1 entries)

More bootloaders may be added in future releases.

---

## Installation

Clone the repository

```bash
git clone https://github.com/seba970423/intel-pstate-governor-tool.git
cd intel-pstate-governor
```

Preview everything without making changes

```bash
sudo ./install.sh --dry-run
```

Install

```bash
sudo ./install.sh
```

The installer will guide you through the entire process.

Example:

```
Intel P-state Governor Setup

CPU: Intel Core i5-8265U
Driver: intel_pstate
Governor: powersave

Enable passive mode? [Y/n]

Available governors

1. ondemand
2. schedutil
3. performance
4. powersave
5. conservative

Select governor:
```

---

## Status

Check the current configuration

```bash
./status.sh
```

Example output

```
Intel P-state Governor Status

Scaling driver:       intel_cpufreq
Configured governor:  ondemand
Active governor:      ondemand
Available governors:  conservative ondemand performance powersave schedutil userspace
intel_pstate mode:    passive
Kernel parameter:     active
Recorded bootloader:  limine
Service enabled:      enabled
Service active:       active

[ OK ] The configured governor is active.
```

---

## Uninstall

```bash
sudo ./uninstall.sh
```

The uninstaller:

- removes the service
- removes the helper
- restores the bootloader
- removes the kernel parameter (if added by this project)
- optionally reboots

---

## Dry-run

Preview every action without changing your system.

```bash
sudo ./install.sh --dry-run
```

---

## Safety

This project

- creates bootloader backups
- stores installation state
- can restore previous configuration
- never modifies unsupported bootloaders
- validates available governors
- warns about conflicting services

---

## Tested on

Hardware

- Lenovo ThinkPad T590
- Intel Core i5-8265U

Distribution

- CachyOS

Bootloader

- Limine

Tests performed

- Install
- Reboot
- Status verification
- Uninstall
- Reboot after uninstall

---

## Contributing

Bug reports and pull requests are welcome.

If you discover a bootloader layout that is not currently supported, please open an issue and include:

- distribution
- bootloader
- `/boot` layout
- error message

---

## License

MIT License

---

## Disclaimer

This project **does not claim** that any governor is universally faster, cooler or more power efficient.

Its purpose is simply to automate configuration and make it persistent across reboots.

The most suitable governor depends on your hardware, kernel, firmware and workload.
