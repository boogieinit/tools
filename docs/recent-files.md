<!-- SPDX-License-Identifier: MIT -->

# recent-files.sh

List regular files created or modified within a given number of hours. The script searches recursively and defaults to the current directory and a 24-hour creation-time window. When run with `/` as the directory, it skips `/proc`.

## Requirements

Raspberry Pi OS and other Linux distributions with Bash, GNU coreutils (`date` and `stat`), and GNU find. Creation mode needs a filesystem that reports file birth timestamps. It skips files without one. Modification mode uses the file's last content modification timestamp.

## Usage

```text
./recent-files.sh [-t HOURS] [-c] [-m] [DIRECTORY]
```

- `-t HOURS` sets the lookback window in positive whole hours.
- `-c` uses creation time.
- `-m` uses modification time.
- `-h` shows help.

If you pass both `-c` and `-m`, the last one wins.

```bash
./recent-files.sh -t 4 /              # Created in the last 4 hours
./recent-files.sh -m -t 4 /           # Modified in the last 4 hours
./recent-files.sh -c -m -t 4 /        # Modified because -m is last
./recent-files.sh -m -c -t 4 /        # Created because -c is last
```

The script is executable in Git. If you download it separately, run `chmod 755 recent-files.sh` to allow direct execution.
