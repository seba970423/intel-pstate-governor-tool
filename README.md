# Intel P-state Governor Tool

A simple utility for Intel CPUs that automates switching the `intel_pstate` driver into **passive mode**, applies your preferred CPU frequency governor, and keeps it persistent across reboots.

Unlike manually editing bootloader files and system configuration, this tool detects the installed bootloader, configures it automatically, creates backups before making changes, and provides a clean uninstall process.

---

## Features

- Automatic bootloader detection
  - Limine
  - GRUB
  - systemd-boot
  - rEFInd
- Adds or removes the `intel_pstate=passive` kernel parameter
- Switches Intel P-state into passive mode
- Lets you choose your preferred governor
- Creates a systemd service that reapplies the governor at every boot
- Creates backups before modifying bootloader configuration
- Verifies changes during installation and uninstallation
- Interactive installer and uninstaller
- Includes a status utility to display the current CPU governor configuration

---

## Supported Governors

The tool automatically detects which governors are available on your system.

Examples:

- ondemand
- schedutil
- performance
- powersave
- conservative
- userspace

---

## Supported Bootloaders

The installer automatically detects and configures:

- Limine
- GRUB
- systemd-boot
- rEFInd

No manual bootloader editing is required.

---

## Installation

Clone the repository:

```bash
git clone https://github.com/seba970423/intel-pstate-governor-tool.git
cd intel-pstate-governor-tool
```

Run the installer:

```bash
sudo ./install.sh
```

The installer will:

- Detect your bootloader
- Detect available governors
- Ask which governor you want to use
- Add the `intel_pstate=passive` kernel parameter (if needed)
- Install the persistent systemd service
- Create backups of modified bootloader configuration
- Offer to reboot the system

---

## Status

You can check the current configuration at any time:

```bash
./status.sh
```

Example output:

```
Intel P-state Governor Status

Scaling driver:      intel_cpufreq
Configured governor: ondemand
Active governor:     ondemand
intel_pstate mode:   passive
Kernel parameter:    active
Recorded bootloader: limine
Service enabled:     enabled
Service active:      active
```

---

## Uninstallation

Run:

```bash
sudo ./uninstall.sh
```

The uninstaller will:

- Restore the original bootloader configuration
- Remove the `intel_pstate=passive` kernel parameter (if it was added by the installer)
- Remove the systemd service
- Remove installed files
- Verify the bootloader configuration
- Offer to reboot

---

## Requirements

- Intel CPU
- Linux with systemd
- Root privileges
- Supported bootloader

---

## Notes

This tool only manages Intel P-state passive mode.

It does **not**:

- modify CPU frequencies manually
- overclock your processor
- disable turbo boost
- change BIOS settings

---

## Tested On

Desktop Environments

- KDE Plasma
- GNOME

Bootloaders

- Limine
- GRUB
- systemd-boot
- rEFInd

Distributions

- CachyOS

CPU Families

- Intel Core i5-8265U
- Intel Core i5-10400

---

## Troubleshooting

### The selected governor is unavailable

Your system is probably still using the `intel_pstate` driver in active mode.

Reboot the system after installation so the `intel_pstate=passive` kernel parameter can take effect.

---

### The service failed to start

Check the service log:

```bash
journalctl -u intel-pstate-governor.service
```

---

### GNOME does not reboot after installation

Recent versions use:

```bash
systemctl reboot -i
```

after explicit confirmation from the user to avoid GNOME session inhibitors preventing a requested reboot.

---

## License

MIT License
