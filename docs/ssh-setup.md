<!-- SPDX-License-Identifier: MIT -->

# ssh-setup.sh

Set up passwordless SSH login to a remote machine in one step. It creates a key if you don't have one, installs it on the remote system, and can save a short name so you can type `ssh homelab` instead of the full user, host, port and key.

## What it does

1. **Key.** Creates a key at `~/.ssh/<name>` (ed25519 by default, with an optional passphrase), or reuses the one that is already there, whatever its type. Before changing anything it checks that the key type will work with this computer and the server (see [Key types and older systems](#key-types-and-older-systems)).
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
./ssh-setup.sh -t rsa oldserver       # RSA key, for servers too old for the default
```

| Option | Description |
|--------|-------------|
| `-u USER` | Remote username (default: asked, offering your local username) |
| `-p PORT` | Remote SSH port, 1 to 65535 (default: 22) |
| `-k NAME` | Key name or path, for example `-k homelab` means `~/.ssh/homelab` (default: asked) |
| `-t TYPE` | Type of key to create: `ed25519` (default), `rsa` (4096-bit, for older systems) or `ecdsa`. Only used when the key doesn't exist yet. DSA is not supported |
| `-a ALIAS` | Short name for `ssh`. Adds a `Host` entry for it to `~/.ssh/config` automatically. Letters, numbers, `.`, `-` and `_` only |
| `-h` | Show help |

## Key types and older systems

The default key type is **ed25519**, which is the current recommendation: strong, short and fast. It needs OpenSSH 6.5 (released in 2014) or newer on **both** this computer and the server. For anything older, use `-t rsa`.

| Type | Use it for | Notes |
|------|------------|-------|
| `ed25519` (default) | Anything reasonably current | Needs OpenSSH 6.5 or newer |
| `rsa` | Older servers, or anything that rejects ed25519 | Created as 4096 bits. Works with every version of OpenSSH |
| `ecdsa` | Rarely needed | 521-bit. Needs OpenSSH 5.7 or newer. Ed25519 or RSA is usually the better choice |
| DSA | Not supported | OpenSSH turned it off by default in 7.0 (2015) and removed it in 9.8, and it is limited to 1024 bits, so current clients refuse it |

**What is checked before anything is changed:**

- **This computer.** The script asks your `ssh` whether it can create the key type, rather than reading a version number. A distribution-patched or home-compiled OpenSSH is therefore judged by what it can really do. If it can't, the script stops and suggests `-t rsa`.
- **The server.** The script reads the server's version banner, which needs no login, and stops if the server is OpenSSH and older than the key type needs. It prints "Nothing has been changed" and the exact command to run again with `-t rsa`. The banner shows the upstream OpenSSH version, so distribution builds and home-compiled servers both report correctly.
- **When it can't tell.** If the server isn't OpenSSH (for example Dropbear or router firmware) or the banner can't be read, the check is skipped and the script carries on. If the final login test then fails, the message says an old server may be the reason.
- **An existing key** is reused whatever its type, and a server check is made for that type too. Asking for a different type with `-t` than the existing key's is an error, so you never get a surprise.

**Very old servers.** Choosing RSA gets you past the key-type problem, but not necessarily all of it. Servers older than OpenSSH 7.2 only accept RSA signatures made with SHA-1, which OpenSSH clients since 8.8 refuse by default, and such servers may also need old key-exchange or cipher settings. Those settings weaken security and should be turned on deliberately, one server at a time, in `~/.ssh/config` (for example `PubkeyAcceptedAlgorithms +ssh-rsa`, and sometimes `HostKeyAlgorithms +ssh-rsa`). This script does not do that for you, and its final failure message mentions it.

## The `~/.ssh/config` entry

With `-a homelab`, a block like this is added to `~/.ssh/config`:

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
- **Placed above any wildcard block that matches it.** `ssh` uses the *first* value it finds for each option, so a catch-all block such as `Host *` that sits above an entry would override it (for example, a `User` set in `Host *` would beat the user in your new entry). If the file already has a block whose pattern matches the new name, such as `Host *`, `Host *.example.com`, `Host nas*` or `Match all`, the new entry is inserted just above it, together with any comment lines directly above that block. A pattern that excludes the name (`Host * !homelab`) doesn't count. A copy of your previous config is saved first, next to it, as `config.bak-<date>-<time>`.
  - **No matching block:** the entry is simply added at the end, and no backup is made.
  - **Symlinked config:** if `~/.ssh/config` is a symlink (for example from a dotfiles setup), the file it points to is updated and the link is kept.
  - **Only that one file is read.** Files pulled in with `Include` aren't searched.
- **Existing entries are never changed.** Nothing is rewritten or reordered; the new entry is only added. A name that is already used (even as the second name on a line such as `Host foo homelab`) is left alone.
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
