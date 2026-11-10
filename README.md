# tools

Small command-line scripts.

| Script | Description |
|--------|-------------|
| [`perfview.sh`](perfview.sh) | Lists the top 5 processes by CPU, memory, disk I/O and network use. Works on macOS and Linux. |
| [`pi-check.sh`](pi-check.sh) | Raspberry Pi 5 health check with optional e-mail alerting. |

## pi-check.sh

Checks CPU temp, throttling / under-voltage, fan, load, memory, swap, disk space, inodes, read-only filesystems, failed systemd units, clock sync, network reachability, kernel errors, unexpected reboots, and NVMe SMART health (only when run as root with `smartctl`).

Run `./pi-check.sh --help` for the options, including e-mail alerting.

## Usage

Make a script executable, then run it:

    chmod +x <script>
    ./<script>

## License

MIT - see [LICENSE](LICENSE).
