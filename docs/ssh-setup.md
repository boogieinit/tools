<!-- SPDX-License-Identifier: MIT -->

# ssh-setup.sh

Set up passwordless SSH login to a remote machine in one step. It creates a key if you don't have one, installs it on the remote system, and can save a short name so you can type `ssh homelab` instead of the full user, host, port and key.

## What it does

1. **Key.** Creates an ed25519 key at `~/.ssh/<name>` (with an optional passphrase), or reuses the one that is already there.
2. **Install.** Copies the public key to the remote account with `ssh-copy-id`, or a built-in equivalent if that isn't available. It asks for the remote password once.
3. **Agent.** Adds the key to `ssh-agent` (and the Keychain on a Mac), so you aren't asked for the passphrase every time.
4. **Short name.** Saves a `Host` entry in `~/.ssh/config`. If you gave an alias with `-a` it does this automatically; otherwise it asks.
5. **Test.** Checks that passwordless login works and prints the exact command to connect.

## Requirements

OpenSSH (`ssh` and `ssh-keygen`). `ssh-copy-id` is used when present. The remote system must allow password login for the first copy of the key.

## Usage

```bash
./ssh-setup.sh                        # fully interactive
./ssh-setup.sh user@host              # remote username given inline
./ssh-setup.sh host                   # asks for the remote username
./ssh-setup.sh -u bob -p 2222 host    # options
./ssh-setup.sh -a homelab bob@host    # also saves 'ssh homelab' in ~/.ssh/config
```

| Option | Description |
|--------|-------------|
| `-u USER` | Remote username (default: asked, offering your local username) |
| `-p PORT` | Remote SSH port, 1 to 65535 (default: 22) |
| `-k NAME` | Key name or path, for example `-k homelab` means `~/.ssh/homelab` (default: asked) |
| `-a ALIAS` | Short name for `ssh`. Adds a `Host` entry for it to `~/.ssh/config` automatically. Letters, numbers, `.`, `-` and `_` only |
| `-h` | Show help |

## The `~/.ssh/config` entry

With `-a homelab`, a block like this is added to the end of `~/.ssh/config`:

```
Host homelab
    HostName 192.168.1.20
    User bob
    Port 22
    IdentityFile /Users/you/.ssh/homelab
    AddKeysToAgent yes
    UseKeychain yes
```

After that, `ssh homelab` is all you type, and so is `scp` or `rsync` with `homelab:` as the host.

- **Automatic with `-a`, optional without it.** Giving `-a` is treated as a clear request, so there is no extra question. Without it, the script asks whether to add an entry and what to call it, and the default answer is yes.
- **Existing entries are never changed.** The file is only ever appended to, and a name that is already used (even as the second name on a line such as `Host foo homelab`) is left alone.
  - If the existing entry points to the same host, the script says so and moves on.
  - If it points somewhere else, the script warns you and prints the full `ssh user@host -p ... -i ...` command instead of the alias, so you don't connect to the wrong machine. Use a different `-a` name for a separate entry.
- **Safe names only.** An alias with a space or a wildcard such as `*` is refused before anything happens, because it could match every host.
- **Permissions.** `~/.ssh` is set to 700 and the config file to 600.
- **`UseKeychain` is macOS only.** That line is left out on other systems, because their `ssh` rejects it.

## Notes

- **It changes two things:** the remote account's `authorized_keys` (your public key is added) and your local `~/.ssh/config`.
- **Running it again is safe.** The existing key is reused, and `ssh-copy-id` does not install a key that is already there. The built-in fallback would add it a second time.
- **Use a passphrase** when it offers one. On a Mac the Keychain remembers it, so you aren't asked repeatedly.
- **If the final test fails,** check that the remote `sshd` allows key login, that `~/.ssh` is 700 and that `~/.ssh/authorized_keys` is 600 on the remote system.
