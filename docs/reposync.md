<!-- SPDX-License-Identifier: MIT -->

# reposync.sh

Pull updates for the current branch of each selected repository with `git pull --ff-only`, then show its short status. If a pull fails, the script continues to the next repository and exits with an error.

Requires Bash and Git.

## Usage

```bash
./reposync.sh -a "$HOME/git"
./reposync.sh -r "my repo" "$HOME/git"
GIT_REPO_ROOT="$HOME/git" ./reposync.sh -r tools
```

- `-a` processes all immediate Git repository folders. This is the default.
- `-r REPO` processes one immediate repository folder by name.
- `-h` shows help.

If both `-a` and `-r` are given, the last one wins. The optional directory argument takes precedence over `GIT_REPO_ROOT`. With neither set, the script checks the current directory.
