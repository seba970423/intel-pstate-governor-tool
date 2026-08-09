# intel-pstate-governor

Current development release: **v0.5.0**

A reversible Intel P-state configurator for systemd-based Linux systems.

During installation, the script detects the governors available on every CPUFreq policy and presents a numbered menu. The selected governor is stored in `/etc/intel-pstate-governor.conf` and reapplied at boot by a systemd oneshot service.

The installer can also add `intel_pstate=passive` through a supported bootloader handler.

## Supported in v0.2.0

- Intel x86_64 CPUs
- systemd
- GRUB
- Limine
- CachyOS systemd-boot-manager using persistent `LINUX_OPTIONS` in `/etc/sdboot-manage.conf`
- Generic systemd-boot using `/etc/kernel/cmdline` or plain Type #1 entries as fallbacks
- Interactive governor selection
- `--governor NAME`
- Dry-run mode
- State-aware uninstall
- Conflict detection
- Status reporting

Unknown bootloader layouts are refused rather than guessed.

## Compatibility

Limine — tested across system/kernel updates; persistence validated on both desktop and laptop.
systemd-boot — persistence validated across updates.
GRUB — validated on Linux Mint, including a kernel update + reboot.
rEFInd — validated by installing and booting an entirely new kernel (linux-cachyos-rc); intel_pstate=passive carried over correctly.

## Install

```bash
git clone https://github.com/seba970423/intel-pstate-governor-tool.git
cd intel-pstate-governor
sudo ./install.sh --dry-run
sudo ./install.sh
```

Example menu:

```text
Available governors
  1. conservative
  2. ondemand
  3. performance
  4. powersave
  5. schedutil

Select a governor [2]:
```

Non-interactive selection:

```bash
sudo ./install.sh --governor ondemand
```

Fully non-interactive:

```bash
sudo ./install.sh --kernel-parameter --governor ondemand --yes
```

Only governors available on every detected CPUFreq policy are accepted.

## Status

```bash
./status.sh
```

Output includes:

- configured governor;
- active governor;
- common available governors;
- scaling driver;
- Intel P-state mode;
- kernel parameter status;
- service state;
- possible conflicting services.

## Uninstall

```bash
sudo ./uninstall.sh
```

Preview removal:

```bash
sudo ./uninstall.sh --dry-run
```

Purge state and backups:

```bash
sudo ./uninstall.sh --purge-state
```

## Installed files

```text
/etc/intel-pstate-governor.conf
/etc/systemd/system/intel-pstate-governor.service
/usr/local/libexec/intel-pstate-governor/apply-governor
/var/lib/intel-pstate-governor/
/var/log/intel-pstate-governor.log
```

## Important

This project does not promise higher FPS, lower latency, improved thermals or better battery life. It automates a configuration choice. Results depend on CPU, firmware, kernel and workload.


## Upgrading an existing v0.2.0 installation

v0.2.0 created the state file as root-only. To let the updated `status.sh` read the recorded bootloader without reinstalling:

```bash
sudo chmod 0644 /var/lib/intel-pstate-governor/state
```

A fresh v0.2.1 installation applies this permission automatically.


## systemd-boot notes

On CachyOS installations that provide `systemd-boot-manager`, the tool uses:

```text
/etc/sdboot-manage.conf
```

and adds `intel_pstate=passive` to the persistent `LINUX_OPTIONS` value. It then runs:

```bash
sdboot-manage gen
```

to regenerate the Boot Loader Specification entries. This prevents kernel or system updates from erasing the parameter when the entries are rebuilt.

For other systemd-boot layouts, the previous generic `/etc/kernel/cmdline` and Type #1 loader-entry backends remain available as fallbacks.

## Transactional uninstall

v0.2.9 restores and verifies the recorded bootloader configuration before removing installed files or state. Failed restoration preserves recovery information.


## v0.3.0 state-management correction

The Limine handler now always records the exact configuration file it uses:

```text
BOOTLOADER=limine
BOOT_CONFIG=/path/to/limine.conf
BOOT_CONFIG_METHOD=limine-config
PARAMETER_ADDED=0|1
```

The uninstaller refuses to guess a missing path, creates a pre-uninstall backup,
removes only the exact `intel_pstate=passive` token, and verifies the token is
gone before deleting project state.


## rEFInd support

rEFInd detection is added after the existing systemd-boot, GRUB, and Limine
checks. It recognizes CachyOS installations with the ESP mounted at `/boot`,
including `/boot/EFI/refind/refind_x64.efi`, and falls back to EFI variables.

The tool edits discovered `refind_linux.conf` files, creates backups, records
every modified path, and verifies both installation and removal.


## Limine persistence (v0.4.0)

On Limine installations that provide `/etc/default/limine` together with
`limine-mkinitcpio` or `limine-update`, the tool now writes
`intel_pstate=passive` to the persistent `KERNEL_CMDLINE` source and then
regenerates the Limine boot configuration. This prevents kernel/package
updates from erasing the parameter when `/boot/limine.conf` is regenerated.

For other Limine layouts, the previous direct `limine.conf` backend remains
available as a fallback. GRUB, systemd-boot, and rEFInd behavior is unchanged.


## systemd-boot-manager persistence (v0.5.0)

CachyOS `sdboot-manage` generates loader entries from `LINUX_OPTIONS` in `/etc/sdboot-manage.conf`. v0.5.0 therefore treats that file as the persistent source of truth instead of editing generated loader entries or `/etc/kernel/cmdline` first. The uninstaller removes only the exact `intel_pstate=passive` token from `LINUX_OPTIONS`, regenerates entries, and verifies removal.

## License

MIT
