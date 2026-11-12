<!-- SPDX-License-Identifier: MIT -->

# tools

Small command-line scripts. Each tool has its own page under [`docs/`](docs/) with the details.

| Script | What it does | Details |
|--------|--------------|---------|
| [`perfview.sh`](perfview.sh) | Snapshot of the top resource users: top 5 processes by CPU and memory, plus disk I/O and network activity. macOS and Linux. | [docs/perfview.md](docs/perfview.md) |
| [`pi-health.sh`](pi-health.sh) | Raspberry Pi 5 health check with optional e-mail alerting. | [docs/pi-health.md](docs/pi-health.md) |
| [`recent-files.sh`](recent-files.sh) | List files created or modified within a time window on Linux. | [docs/recent-files.md](docs/recent-files.md) |
| [`reposync.sh`](reposync.sh) | Pull upstream updates with a fast-forward-only merge. | [docs/reposync.md](docs/reposync.md) |
| [`repostatus.sh`](repostatus.sh) | Show the current branch and local status. | [docs/repostatus.md](docs/repostatus.md) |
| [`ssh-setup.sh`](ssh-setup.sh) | Create an SSH key if needed, install it on a remote system for passwordless login, and optionally save a short name in `~/.ssh/config`. | [docs/ssh-setup.md](docs/ssh-setup.md) |

## Usage

Make a script executable, then run it:

    chmod +x <script>
    ./<script>

## Adding a tool

1. Put the script in the top level and make it executable.
2. Add a row to the table above with a one-line description.
3. Add `docs/<script-name>.md` with what it does, what it needs, its options and an example.

## License

MIT - see [LICENSE](LICENSE).
