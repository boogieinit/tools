# perfview.sh

A quick snapshot of what is using your system's resources: the busiest processes by CPU and memory, plus disk I/O and network activity.

## What it shows

| Section | Linux | macOS |
|---------|-------|-------|
| CPU | Top 5 processes by CPU | Top 5 processes by CPU |
| Memory | Top 5 processes by memory | Top 5 processes by memory |
| Disk I/O | Busiest processes, from `iotop` | Disk throughput from `iostat` (system-wide, not per process) |
| Network | Traffic for 5 seconds, from `iftop` (falls back to `netstat`) | Open network connections by process (`lsof`) and the routing table (`netstat`) |

Each section is separated by a line of `#` characters.

## Supported systems

macOS, CentOS and Ubuntu. The script detects the system on startup and prints `Detected OS`. On anything else it still shows the CPU and memory sections.

## Requirements

- `ps`, `sort` and `top` (standard on every supported system). The script exits if `top` is missing.
- `iotop` and `iftop` on Linux, for the I/O and network sections.

**Heads up: it installs software on first run.** If `iotop` or `iftop` is missing, the script tries to install it for you with `yum` (plus `epel-release`) on CentOS, `apt-get` on Ubuntu, or Homebrew on macOS. On Linux that runs with elevated privileges (it uses `sudo`), so you may be asked for your password. The Linux I/O and network sections also run `iotop` and `iftop` with `sudo` every time. If you would rather not have a script install packages, install both tools yourself first, or read the script before running it.

## Usage

    chmod +x perfview.sh
    ./perfview.sh

There are no options. The output goes to the terminal, so redirect it if you want to keep it:

    ./perfview.sh > perfview-$(date +%F).txt
