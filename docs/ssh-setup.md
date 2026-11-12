<!-- SPDX-License-Identifier: MIT -->

# ssh-setup.sh

Set up passwordless SSH login in one step: creates a key if needed, installs it on the remote system, and can save a short name so `ssh homelab` works.

## What it does

1. **Key.** Creates `~/.ssh/<name>` (ed25519 by default) or reuses the existing one, whatever its type. Compatibility is checked first (see [Key types](#key-types)).
2. **Install.** Copies the public key to the remote account (`ssh-copy-id`, or a built-in fallback). Asks for the remote password once.
3. **Agent.** Adds the key to `ssh-agent` (and the Keychain on a Mac).
4. **Config.** Adds a `Host` entry to `~/.ssh/config`: automatically with `-a`, otherwise it asks.
5. **Test.** Confirms key login works and prints the command to connect.

**Requires:** OpenSSH (`ssh`, `ssh-keygen`); `ssh-copy-id` is optional. The remote system must allow password login for the first copy.

## Usage

```bash
./ssh-setup.sh                        # fully interactive
./ssh-setup.sh user@host              # username inline
./ssh-setup.sh -u bob -p 2222 host    # options
./ssh-setup.sh -a homelab bob@host    # also saves 'ssh homelab'
./ssh-setup.sh -t rsa oldserver       # RSA key for an old server
```

| Option | Description |
|--------|-------------|
| `-u USER` | Remote username (default: asked) |
| `-p PORT` | Remote port, 1-65535 (default: 22) |
| `-k NAME` | Key name or path; `-k homelab` means `~/.ssh/homelab` (default: asked) |
| `-t TYPE` | Key type to create: `ed25519` (default), `rsa` or `ecdsa`. If the key already exists, it must be this type |
| `-a ALIAS` | Short name; adds the `~/.ssh/config` entry automatically. Letters, digits, `.`, `-`, `_` only |
| `-h` | Help |

## Key types

| Type | Needs | Notes |
|------|-------|-------|
| `ed25519` (default) | OpenSSH 6.5+ (2014) on both ends | Recommended |
| `rsa` | Any version | 4096-bit. Use for old servers |
| `ecdsa` | OpenSSH 5.7+ | 521-bit; rarely the best choice |
| DSA | Not supported | Off by default since OpenSSH 7.0, removed in 9.8, 1024-bit limit |

**Checked before anything is changed** (otherwise it stops and prints the command to retry with `-t rsa`):

- **This computer** can create the type. Tested by asking `ssh`, not by version number, so patched or compiled builds are judged by capability.
- **The server** is new enough. Read from its version banner (no login). Applies only to OpenSSH servers; Dropbear, router firmware or an unreadable banner is let through, and a failed final login then hints at an old server.

**Very old servers.** RSA fixes the key type, but servers older than OpenSSH 7.2 accept only SHA-1 RSA signatures, which clients 8.8+ refuse by default. They may need weaker legacy settings such as `PubkeyAcceptedAlgorithms +ssh-rsa`, set per server in `~/.ssh/config`. The script does not enable these.

## The `~/.ssh/config` entry

```
Host homelab
    HostName 192.168.1.20
    User bob
    Port 22
    IdentityFile /Users/you/.ssh/homelab
    AddKeysToAgent yes
    UseKeychain yes
```

- **Automatic with `-a`;** without it, the script asks (default yes).
- **Placed above any wildcard block that matches it** (`Host *`, `Host *.example.com`, `Match all`). `ssh` uses the first value it finds, so a matching block above the entry would override it. The entry goes just above that block, with its comments. `config.bak-<timestamp>` is saved first. If nothing matches, the entry is appended and no backup is made.
- **Existing entries are never changed.** An alias already in use is left alone: same host, it says so; different host, it warns and prints the full `ssh user@host -p … -i …` command instead.
- **Unsafe aliases are refused** (spaces, `*`, `?`, `!`) before anything happens.
- **Details:** `~/.ssh` is set to 700 and the config to 600. A symlinked config is updated in place. `Include`d files aren't searched. `UseKeychain` is written on macOS only.

## Notes

- **It changes** the remote `authorized_keys` and your local `~/.ssh/config`.
- **Re-running is safe.** The key is reused, and `ssh-copy-id` skips a key already installed (the built-in fallback would add it again).
- **If the final test fails,** check that the server allows key login, `~/.ssh` is 700 and `authorized_keys` is 600 on the remote.
