#!/usr/bin/env bash
#
# ssh-setup.sh - create an SSH key (if needed) and install it on a remote
# system so you can log in without typing a password. Plus lots of useful options.
#
# Usage:
#   ./ssh-setup.sh                      # fully interactive
#   ./ssh-setup.sh user@host            # remote username given inline
#   ./ssh-setup.sh host                 # prompts for the remote username
#   ./ssh-setup.sh -u bob -p 2222 host  # options
#   ./ssh-setup.sh -a homelab bob@host  # also saves a short name, so 'ssh homelab' works
#
# Options:
#   -u USER   remote username (default: prompt, offering your local username)
#   -p PORT   remote SSH port (default: 22)
#   -k NAME   key name or path (e.g. -k homelab -> ~/.ssh/homelab; default: prompt)
#   -a ALIAS  short name for ssh (e.g. -a homelab -> 'ssh homelab'). When you give one,
#             a Host entry for it is added to ~/.ssh/config automatically. Without -a you
#             are asked whether to add one. An alias may use letters, numbers, . - and _
#             The entry is placed above any wildcard block (such as 'Host *') that also
#             matches it, because ssh uses the first value it finds for each option.
#   -h        show help
#
set -euo pipefail

KEY=""
PORT=22
ALIAS=""
REMOTE_USER=""
HOST=""

usage() { sed -n '3,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# An alias becomes a "Host" line in ~/.ssh/config, so keep it to plain characters:
# a space would define extra names, and * ? ! would match other hosts.
valid_alias() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

# ssh uses the FIRST value it finds for each option, so an entry for one host has to come
# BEFORE any wildcard block (such as "Host *") that also matches it, or that block wins.
# Usage: find_wildcard_block CONFIG ALIAS
# Prints "INSERT_AT HIT_LINE" (the line to insert before, and the matching block's line),
# or nothing if no block in the file matches the alias. Comment lines directly above the
# matching block are treated as part of it, so the new entry goes above them.
find_wildcard_block() {
  awk -v a="$2" '
    function glob2re(p,   i, c, r) {
      r = ""
      for (i = 1; i <= length(p); i++) {
        c = substr(p, i, 1)
        if (c == "*") r = r ".*"
        else if (c == "?") r = r "."
        else if (index("\\.+()[]{}^$|", c)) r = r "\\" c
        else r = r c
      }
      return "^" r "$"
    }
    { line[NR] = $0 }
    !hit && tolower($1) == "host" {
      pos = 0; neg = 0
      for (i = 2; i <= NF; i++) {
        t = $i
        if (substr(t, 1, 1) == "!") { if (a ~ glob2re(substr(t, 2))) neg = 1 }
        else if (a ~ glob2re(t)) pos = 1
      }
      if (pos && !neg) hit = NR
    }
    !hit && tolower($1) == "match" && tolower($2) == "all" { hit = NR }
    END {
      if (hit) {
        n = hit
        while (n > 1 && line[n - 1] ~ /^[[:space:]]*#/) n--
        print n, hit
      }
    }
  ' "$1"
}

while getopts "u:p:k:a:h" opt; do
  case "$opt" in
    u) REMOTE_USER="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    k) KEY="${OPTARG/#\~/$HOME}"
       [[ "$KEY" == */* ]] || KEY="$HOME/.ssh/$KEY" ;;
    a) ALIAS="$OPTARG" ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND - 1))

# Check the options before touching anything
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( 10#$PORT < 1 || 10#$PORT > 65535 )); then
  echo "Error: the port must be a number from 1 to 65535 (got '$PORT')." >&2
  exit 1
fi
if [[ -n "$ALIAS" ]] && ! valid_alias "$ALIAS"; then
  echo "Error: an alias may only contain letters, numbers, dots, dashes and underscores (got '$ALIAS')." >&2
  exit 1
fi

# Target can be "user@host" or just "host"
if [[ $# -ge 1 ]]; then
  TARGET="$1"
  if [[ "$TARGET" == *@* ]]; then
    REMOTE_USER="${TARGET%%@*}"
    HOST="${TARGET#*@}"
  else
    HOST="$TARGET"
  fi
fi

# Prompt for anything still missing
if [[ -z "$HOST" ]]; then
  read -r -p "Remote host (name or IP): " HOST
fi
[[ -n "$HOST" ]] || { echo "Error: a host is required." >&2; exit 1; }

if [[ -z "$REMOTE_USER" ]]; then
  read -r -p "Remote username [$(id -un)]: " REMOTE_USER
  REMOTE_USER="${REMOTE_USER:-$(id -un)}"
fi

if [[ -z "$KEY" ]]; then
  echo "Key name examples: work_laptop, homelab, github_personal"
  read -r -p "Key name [id_ed25519]: " KEYNAME
  KEYNAME="${KEYNAME:-id_ed25519}"
  [[ "$KEYNAME" == */* ]] && KEY="${KEYNAME/#\~/$HOME}" || KEY="$HOME/.ssh/$KEYNAME"
fi

echo
echo "Remote : ${REMOTE_USER}@${HOST} (port ${PORT})"
echo "Key    : ${KEY}"
[[ -z "$ALIAS" ]] || echo "Alias  : ${ALIAS} (will be saved in ~/.ssh/config)"
echo

# 1. Create the key if it doesn't exist yet
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY" ]]; then
  echo "[1/4] Key already exists, reusing it."
else
  echo "[1/4] Generating a new ed25519 key (you'll be asked for an optional passphrase)..."
  ssh-keygen -t ed25519 -a 100 -f "$KEY" -C "${LOGNAME:-$(id -un)}@$(hostname -s)-$(basename "$KEY")"
fi

# Make sure the public half exists (rebuild it from the private key if missing)
if [[ ! -f "${KEY}.pub" ]]; then
  ssh-keygen -y -f "$KEY" > "${KEY}.pub"
fi

# 2. Copy the public key to the remote system (asks for the remote password once)
echo
echo "[2/4] Copying public key to ${REMOTE_USER}@${HOST} (enter the remote password when prompted)..."
if command -v ssh-copy-id >/dev/null 2>&1; then
  ssh-copy-id -i "${KEY}.pub" -p "$PORT" "${REMOTE_USER}@${HOST}"
else
  # Fallback if ssh-copy-id isn't available
  ssh -p "$PORT" "${REMOTE_USER}@${HOST}" \
    'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; cat >> ~/.ssh/authorized_keys' \
    < "${KEY}.pub"
fi

# 3. Load the key into the macOS agent/Keychain so a passphrase isn't asked every time
echo
echo "[3/4] Adding key to ssh-agent and the macOS Keychain..."
ssh-add --apple-use-keychain "$KEY" 2>/dev/null || ssh-add "$KEY" 2>/dev/null || \
  echo "      (Skipped - ssh-agent not available. Not a problem if the key has no passphrase.)"

# Save a Host entry so you can just type "ssh <alias>".
# If -a gave an alias, that is a clear request, so the entry is added without asking.
# Otherwise offer to add one.
CONFIG="$HOME/.ssh/config"
CONFIG_RESULT="skipped"      # added, already-there, points-elsewhere or skipped

if [[ -z "$ALIAS" ]]; then
  echo
  read -r -p "Add a ~/.ssh/config entry (remembers user, port and key; lets you use a short alias)? [Y/n] " ANS
  if [[ ! "${ANS:-Y}" =~ ^[Nn] ]]; then
    read -r -p "Short alias to type instead of the full name [${HOST}]: " ALIAS
    ALIAS="${ALIAS:-$HOST}"
    if ! valid_alias "$ALIAS"; then
      echo "      Skipping the ~/.ssh/config entry: '${ALIAS}' may only contain letters, numbers, dots, dashes and underscores."
      ALIAS=""
    fi
  fi
fi

if [[ -n "$ALIAS" ]]; then
  echo
  touch "$CONFIG"
  chmod 600 "$CONFIG"
  # Is the alias already used by a Host line? (It may be any name on that line.)
  if awk -v a="$ALIAS" 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i == a) found = 1 } END { exit !found }' "$CONFIG"; then
    existing_host="$(ssh -F "$CONFIG" -G "$ALIAS" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')"
    if [[ "$existing_host" == "$HOST" ]]; then
      CONFIG_RESULT="already-there"
      echo "      A Host entry for ${ALIAS} already exists in ${CONFIG} and points to ${HOST}; leaving it alone."
    else
      CONFIG_RESULT="points-elsewhere"
      echo "      WARNING: ${CONFIG} already has a Host entry named ${ALIAS}, and it points to" >&2
      echo "      ${existing_host:-a different place}, not ${HOST}. Leaving it alone." >&2
      echo "      Run again with a different -a name if you want a separate entry for ${HOST}." >&2
    fi
  else
    # Build the entry first
    ENTRY="$(mktemp)"
    {
      echo "Host ${ALIAS}"
      echo "    HostName ${HOST}"
      echo "    User ${REMOTE_USER}"
      echo "    Port ${PORT}"
      if [[ "$KEY" == *" "* ]]; then
        echo "    IdentityFile \"${KEY}\""
      else
        echo "    IdentityFile ${KEY}"
      fi
      echo "    AddKeysToAgent yes"
      # UseKeychain only exists in macOS's ssh; other systems reject it as a bad option
      if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "    UseKeychain yes"
      fi
    } > "$ENTRY"

    # If a wildcard block such as "Host *" already matches this alias, put the new entry
    # above it (otherwise that block's settings would win). If not, add it at the end.
    INSERT_INFO="$(find_wildcard_block "$CONFIG" "$ALIAS")"
    if [[ -z "$INSERT_INFO" ]]; then
      { echo; cat "$ENTRY"; } >> "$CONFIG"
      echo "      Added a Host entry for ${ALIAS} to ${CONFIG}."
    else
      read -r INSERT_AT HIT_LINE <<< "$INSERT_INFO"
      HIT_TEXT="$(sed -n "${HIT_LINE}p" "$CONFIG" | sed 's/^[[:space:]]*//')"
      BACKUP="${CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
      cp -p "$CONFIG" "$BACKUP"
      NEWCFG="$(mktemp)"
      {
        awk -v n="$INSERT_AT" 'NR < n' "$CONFIG"      # the lines above the insertion point (none if it is line 1)
        # keep a blank line between the entry above and the new one
        if (( INSERT_AT > 1 )) && [[ -n "$(sed -n "$((INSERT_AT - 1))p" "$CONFIG" | tr -d '[:space:]')" ]]; then
          echo
        fi
        cat "$ENTRY"
        echo
        awk -v n="$INSERT_AT" 'NR >= n' "$CONFIG"      # the rest, starting with the matching block
      } > "$NEWCFG"
      cat "$NEWCFG" > "$CONFIG"   # writes through a symlink and keeps the file's permissions
      rm -f "$NEWCFG"
      echo "      Added a Host entry for ${ALIAS} to ${CONFIG}, above the block \"${HIT_TEXT}\""
      echo "      (ssh uses the first value it finds, so a matching block lower down can't override it)."
      echo "      Your previous config is saved as ${BACKUP}."
    fi
    rm -f "$ENTRY"
    CONFIG_RESULT="added"
  fi
fi

# 4. Verify passwordless login works
echo
echo "[4/4] Testing passwordless login..."
if ssh -o BatchMode=yes -o PasswordAuthentication=no -i "$KEY" -p "$PORT" \
     "${REMOTE_USER}@${HOST}" 'echo "Login OK as $(whoami) on $(hostname)"'; then
  echo
  case "$CONFIG_RESULT" in
    added|already-there)
      echo "Done. Connect with:  ssh ${ALIAS}"
      ;;
    *)
      # No usable alias, so spell out everything ssh needs
      CONNECT="ssh ${REMOTE_USER}@${HOST}"
      [[ "$PORT" == 22 ]] || CONNECT+=" -p ${PORT}"
      [[ "$KEY" == "$HOME/.ssh/id_ed25519" ]] || CONNECT+=" -i ${KEY}"
      echo "Done. Connect with:  ${CONNECT}"
      ;;
  esac
else
  echo
  echo "Key-based login did not work. Check that the remote sshd allows pubkey auth" >&2
  echo "and that ~/.ssh is 700 and ~/.ssh/authorized_keys is 600 on the remote." >&2
  exit 1
fi
