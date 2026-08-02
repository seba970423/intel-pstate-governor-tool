# Contributing

Bug reports and tested bootloader improvements are welcome.

Please include:

- distribution and version;
- kernel version (`uname -r`);
- CPU model;
- bootloader;
- `./status.sh` output;
- relevant lines from `/var/log/intel-pstate-ondemand.log`.

Do not include secrets, private mount paths or unrelated logs.

Before opening a pull request:

```bash
shellcheck install.sh uninstall.sh status.sh lib/*.sh src/apply-governor
```

Keep bootloader edits conservative: when a layout cannot be identified safely, report it instead of guessing.
