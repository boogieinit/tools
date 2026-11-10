# pi-health.sh

Raspberry Pi 5 health check with optional e-mail alerting.

## What it checks

CPU temp, throttling / under-voltage, fan, load, memory, swap, disk space, inodes, read-only filesystems, failed systemd units, clock sync, network reachability, kernel errors, unexpected reboots, and NVMe SMART health (only when run as root with `smartctl`).

Each check reports OK, a warning, or critical. The exit status of the script reflects the worst result:

| Exit status | Meaning |
|-------------|---------|
| 0 | Everything OK |
| 1 | One or more warnings |
| 2 | One or more critical problems |
| 3 | Usage error (bad option) |

## Usage

    ./pi-health.sh                       # full report to the terminal
    ./pi-health.sh -q                    # print nothing unless there is a problem
    ./pi-health.sh -q -m me@example.com  # e-mail only when something is wrong
    ./pi-health.sh --test-mail -m me@example.com   # check that mail delivery works

Run it as root to include the NVMe SMART check.

## Options

| Option | Description |
|--------|-------------|
| `-m, --mail ADDR` | E-mail ADDR when problems are found, and again when they clear |
| `-f, --from ADDR` | Optional From: address for the e-mail |
| `-r, --repeat HOURS` | Re-send a still-active alert every HOURS (default 12, 0 = every run) |
| `--crit-only` | Only e-mail for critical problems, not warnings |
| `--force-mail` | Send the e-mail now regardless of state (shows the full report) |
| `--test-mail` | Send a test e-mail to verify mail delivery, then exit |
| `-q, --quiet` | Print nothing when everything is healthy |
| `-l, --log FILE` | Append a one-line summary of every run to FILE, for trend history |
| `-c, --config FILE` | Read threshold overrides from FILE (plain shell `VAR=value` lines) |
| `--ping-host HOST` | Host to ping for the network check (default 1.1.1.1) |
| `--no-net` | Skip the network check |
| `-h, --help` | Show the built-in help |

## Thresholds

Defaults can be changed with environment variables or a config file (`-c`). For example: `WARN_TEMP=65 ./pi-health.sh`.

| Check | Warning | Critical |
|-------|---------|----------|
| CPU temperature | `WARN_TEMP` 70 C | `CRIT_TEMP` 80 C |
| Filesystem used | `WARN_DISK` 80% | `CRIT_DISK` 90% |
| Inodes used | `WARN_INODE` 80% | `CRIT_INODE` 90% |
| Memory used (excluding cache) | `WARN_MEM` 85% | `CRIT_MEM` 95% |
| Swap used | `WARN_SWAP` 50% | `CRIT_SWAP` 80% |
| Load (15-minute average per core) | `WARN_LOAD` 1.0 | `CRIT_LOAD` 2.0 |

Other settings: `FAN_CHECK_TEMP` (a fan at 0 rpm above this temperature, default 60 C, is a problem), `REBOOT_WINDOW_MIN` (warn if the system has been up less than this many minutes, default 75, which suits an hourly cron job), `LOG_WINDOW` (how far back to scan the kernel log, default "1 hour ago") and `PING_HOST`.

## E-mail alerts

Alerts need a mail program on the Pi: `msmtp`, `sendmail`, or a mail command such as `bsd-mailx`. Use `--test-mail` to confirm it works. The script remembers the last alert it sent (in `~/.local/state/pi-health/` by default, or `PI_HEALTH_STATE_DIR`) so it does not repeat itself every run. It re-sends a still-active problem after the `--repeat` interval and e-mails again when the problem clears.

## Running it on a schedule

Hourly with cron, e-mailing only when something is wrong and keeping a log:

    0 * * * * /usr/local/bin/pi-health.sh -q -m me@example.com -l /var/log/pi-health.log >/dev/null 2>&1
