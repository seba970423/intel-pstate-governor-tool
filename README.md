# intel-pstate-governor


A reversible Intel P-state configurator for systemd-based Linux systems.

During installation, the script detects the governors available on every CPUFreq policy and presents a numbered menu. The selected governor is stored in `/etc/intel-pstate-governor.conf` and reapplied at boot by a systemd oneshot service.

The installer can also add `intel_pstate=passive` through a supported bootloader handler.

## Supported

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

Limine, system-d boot, Grub and rEFInd.

## Preview Install
```bash
sudo ./install.sh --dry-run
```

## Install

```bash
git clone https://github.com/seba970423/intel-pstate-governor-tool.git
cd intel-pstate-governor
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

## License

MIT
