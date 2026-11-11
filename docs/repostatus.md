<!-- SPDX-License-Identifier: MIT -->

# repostatus.sh

Show the current branch and short status of each selected repository. Ahead and behind counts use Git's locally stored upstream information.

Requires Bash and Git.

## Usage

```bash
./repostatus.sh -a "$HOME/git"
./repostatus.sh -r "my repo" "$HOME/git"
GIT_REPO_ROOT="$HOME/git" ./repostatus.sh -r tools
```

- `-a` processes all immediate Git repository folders. This is the default.
- `-r REPO` processes one immediate repository folder by name.
- `-h` shows help.

If both `-a` and `-r` are given, the last one wins. The optional directory argument takes precedence over `GIT_REPO_ROOT`. With neither set, the script checks the current directory.
