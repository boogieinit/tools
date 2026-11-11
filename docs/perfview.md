<!-- SPDX-License-Identifier: MIT -->

# perfview.sh

A quick snapshot of what is using your system's resources: the busiest processes by CPU and memory, plus disk I/O and network activity.

## What it shows

| Section | Linux | macOS |
|---------|-------|-------|
| CPU | Top 5 processes by CPU | Top 5 processes by CPU |
| Memory | Top 5 processes by memory | Top 5 processes by memory |
| Disk I/O | Busiest processes, from `iotop` | Disk throughput from `iostat` (system-wide, not per process) |
| Network | Traffic for 5 seconds, from `iftop` | Open network connections by process (`lsof`) and the routing table (`netstat`) |

Each section is separated by a line of `#` characters.

## Supported systems

macOS, CentOS and Ubuntu. The script detects the system on startup and prints `Detected OS`.

## Requirements

The script checks for the programs it needs before doing anything else. **It never installs software.** If something is missing, it lists the missing programs and exits, along with the command you will likely need to run on that system.

| System | Required programs |
|--------|-------------------|
| All | `ps`, `sort`, `head`, `top` |
| Linux | `iotop`, `iftop`, `sudo`, `timeout` |
| macOS | `iostat`, `lsof`, `netstat` (all built into macOS) |

Example of the message on Ubuntu when `iotop` and `iftop` are missing:

    The following required programs are not installed:
      - iotop
      - iftop

    Please install them, then run this script again. You will likely need to run:
      sudo apt-get update
      sudo apt-get install -y iotop iftop

On CentOS the hint uses `yum` (and adds `epel-release`, which provides `iotop` and `iftop`). On a system the script doesn't recognize, it lists the packages and leaves the choice of package manager to you.

On Linux the I/O and network sections run `iotop` and `iftop` with `sudo`, so you may be asked for your password.

## Usage

    chmod +x perfview.sh
    ./perfview.sh

There are no options. The output goes to the terminal, so redirect it if you want to keep it:

    ./perfview.sh > perfview-$(date +%F).txt
