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
#   ./ssh-setup.sh -t rsa oldserver     # RSA key, for servers too old for the default
#
# Options:
#   -u USER   remote username (default: prompt, offering your local username)
#   -p PORT   remote SSH port (default: 22)
#   -k NAME   key name or path (e.g. -k homelab -> ~/.ssh/homelab; default: prompt)
#   -t TYPE   type of key to create: ed25519 (default), rsa (4096-bit, works on old
#             servers) or ecdsa. Only used when the key doesn't exist yet. DSA is not
#             supported. Before changing anything, the script checks that this computer
#             can create that type and that the server, if it is OpenSSH, is new enough:
#             ed25519 needs OpenSSH 6.5 (2014) or newer, ecdsa 5.7, rsa any version.
#   -a ALIAS  short name for ssh (e.g. -a homelab -> 'ssh homelab'). When you give one,
#             a Host entry for it is added to ~/.ssh/config automatically. Without -a you
#             are asked whether to add one. An alias may use letters, numbers, . - and _
#             The entry is placed above any wildcard block (such as 'Host *') that also
#             matches it, because ssh uses the first value it finds for each option.
#   -h        show help
#
set -euo pipefail

KEY=""
KEYTYPE="ed25519"
KEYTYPE_GIVEN=0
PORT=22
ALIAS=""
REMOTE_USER=""
HOST=""

usage() { sed -n '3,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# An alias becomes a "Host" line in ~/.ssh/config, so keep it to plain characters:
# a space would define extra names, and * ? ! would match other hosts.
valid_alias() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

# --- Compatibility checks -------------------------------------------------------------
# Feature checks are used for THIS computer (what its ssh can actually do), so a
# distribution-patched or home-compiled OpenSSH is judged by capability, not by a version
# number. For the SERVER the only signal is its version banner, which is read without
# logging in. For OpenSSH it is the upstream version, so it is reliable.

# This computer's OpenSSH version, for messages (e.g. "9.6p1"); empty if it can't be read
local_ssh_version() {
  local v
  v="$(ssh -V 2>&1 || true)"
  sed -n 's/^OpenSSH_\([0-9][0-9.]*[a-z0-9]*\).*/\1/p' <<< "$v" | head -n 1
}

# Can this computer's ssh create a key of this type? (rsa always can)
local_can_create() {
  local keys
  keys="$(ssh -Q key 2>/dev/null || true)"
  case "$1" in
    ed25519) grep -qx 'ssh-ed25519' <<< "$keys" ;;
    ecdsa)   grep -q '^ecdsa-sha2-' <<< "$keys" ;;
    *)       return 0 ;;
  esac
}

# Does this computer's ssh-keygen know the -a option (stronger passphrase protection)?
keygen_has_a_option() {
  local usage_text
  usage_text="$(ssh-keygen -? 2>&1 || true)"
  grep -q -- '-a rounds' <<< "$usage_text"
}

# The server's software banner, read without logging in (e.g. "OpenSSH_7.4p1 Debian-10").
# Prints nothing if it can't be read. Uses a throwaway known_hosts, so nothing is recorded.
remote_banner() {
  local out
  out="$(ssh -v -o BatchMode=yes -o ConnectTimeout=8 -o PreferredAuthentications=none \
           -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -p "$PORT" "${REMOTE_USER}@${HOST}" true 2>&1 || true)"
  awk '/remote software version/ { sub(/.*remote software version /, ""); print; exit }' <<< "$out"
}

# True if BANNER is OpenSSH and older than MAJOR.MINOR. False for anything else
# (not OpenSSH, unreadable), because then there is nothing to base a refusal on.
openssh_older_than() {
  local re='^OpenSSH_([0-9]+)\.([0-9]+)'
  [[ "$1" =~ $re ]] || return 1
  local major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}"
  (( major < $2 || (major == $2 && minor < $3) ))
}

# The type of an existing key file (ed25519, rsa, ecdsa, dsa); empty if it can't be told.
# Uses the .pub file when there is one, because that never asks for a passphrase.
key_type_of() {
  local f="$1"
  [[ -f "${1}.pub" ]] && f="${1}.pub"
  ssh-keygen -l -f "$f" 2>/dev/null < /dev/null | awk '{ t = $NF; gsub(/[()]/, "", t); print tolower(t); exit }'
}

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

while getopts "u:p:k:a:t:h" opt; do
  case "$opt" in
    u) REMOTE_USER="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    k) KEY="${OPTARG/#\~/$HOME}"
       [[ "$KEY" == */* ]] || KEY="$HOME/.ssh/$KEY" ;;
    a) ALIAS="$OPTARG" ;;
    t) KEYTYPE="$(printf '%s' "$OPTARG" | tr '[:upper:]' '[:lower:]')"
       KEYTYPE_GIVEN=1 ;;
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
case "$KEYTYPE" in
  ed25519|rsa|ecdsa) ;;
  dsa)
    echo "Error: DSA keys are not supported. OpenSSH turned DSA off by default in version 7.0" >&2
    echo "       (2015) and removed it in 9.8, and DSA keys are limited to 1024 bits, so current" >&2
    echo "       ssh clients refuse them. Use -t rsa instead: it works with almost every server." >&2
    exit 1 ;;
  *)
    echo "Error: unknown key type '$KEYTYPE'. Use ed25519, rsa or ecdsa." >&2
    exit 1 ;;
esac

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
  read -r -p "Key name [id_${KEYTYPE}]: " KEYNAME
  KEYNAME="${KEYNAME:-id_${KEYTYPE}}"
  [[ "$KEYNAME" == */* ]] && KEY="${KEYNAME/#\~/$HOME}" || KEY="$HOME/.ssh/$KEYNAME"
fi

# Which type of key will be used? An existing key is reused, whatever its type.
KEY_EXISTS=0
if [[ -f "$KEY" ]]; then
  KEY_EXISTS=1
  EXISTING_TYPE="$(key_type_of "$KEY" || true)"
  if [[ -n "$EXISTING_TYPE" ]]; then
    if [[ "$KEYTYPE_GIVEN" == 1 && "$EXISTING_TYPE" != "$KEYTYPE" ]]; then
      echo "Error: ${KEY} already exists and is a ${EXISTING_TYPE} key, but -t ${KEYTYPE} was given." >&2
      echo "       Use a different name with -k to create a new ${KEYTYPE} key, or leave out -t to reuse this one." >&2
      exit 1
    fi
    KEYTYPE="$EXISTING_TYPE"
  fi
fi

echo
echo "Remote : ${REMOTE_USER}@${HOST} (port ${PORT})"
if [[ "$KEY_EXISTS" == 1 ]]; then
  echo "Key    : ${KEY} (existing ${KEYTYPE} key)"
else
  echo "Key    : ${KEY} (new ${KEYTYPE} key)"
fi
[[ -z "$ALIAS" ]] || echo "Alias  : ${ALIAS} (will be saved in ~/.ssh/config)"

# Check that this key type will work BEFORE changing anything.
# 1. Can this computer create it? (a capability test, not a version test)
if [[ "$KEY_EXISTS" == 0 ]] && ! local_can_create "$KEYTYPE"; then
  LOCAL_VERSION="$(local_ssh_version)"
  echo >&2
  echo "Error: this computer's ssh${LOCAL_VERSION:+ (OpenSSH ${LOCAL_VERSION})} can't create ${KEYTYPE} keys." >&2
  echo "       Nothing has been changed. Use an RSA key instead:  $(basename "$0") -t rsa ..." >&2
  exit 1
fi
# 2. Is the server new enough to accept it? Only OpenSSH servers can be judged, from the
#    version in their banner. Anything else (or an unreadable banner) is let through.
NEED_MAJOR=0; NEED_MINOR=0
case "$KEYTYPE" in
  ed25519) NEED_MAJOR=6; NEED_MINOR=5 ;;
  ecdsa)   NEED_MAJOR=5; NEED_MINOR=7 ;;
esac
if (( NEED_MAJOR > 0 )); then
  BANNER="$(remote_banner)"
  if [[ -z "$BANNER" ]]; then
    echo "Server : (could not read its version, so it was not checked; continuing)"
  elif openssh_older_than "$BANNER" "$NEED_MAJOR" "$NEED_MINOR"; then
    KEY_BASE="$(basename "$KEY")"
    RSA_NAME="${KEY_BASE/ed25519/rsa}"
    [[ "$RSA_NAME" != "$KEY_BASE" ]] || RSA_NAME="${KEY_BASE}_rsa"
    RETRY="$(basename "$0") -t rsa -k ${RSA_NAME}"
    [[ "$PORT" == 22 ]] || RETRY+=" -p ${PORT}"
    [[ -z "$ALIAS" ]] || RETRY+=" -a ${ALIAS}"
    RETRY+=" ${REMOTE_USER}@${HOST}"
    echo "Server : ${BANNER}"
    echo >&2
    echo "Error: this server is too old for ${KEYTYPE} keys (they need OpenSSH ${NEED_MAJOR}.${NEED_MINOR} or newer)." >&2
    echo "       Nothing has been changed. RSA keys work on older servers; try:" >&2
    echo "         ${RETRY}" >&2
    exit 1
  else
    echo "Server : ${BANNER}"
  fi
fi
echo

# 1. Create the key if it doesn't exist yet
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY" ]]; then
  echo "[1/4] Key already exists, reusing it."
else
  echo "[1/4] Generating a new ${KEYTYPE} key (you'll be asked for an optional passphrase)..."
  KEYGEN_ARGS=(-t "$KEYTYPE")
  case "$KEYTYPE" in
    rsa)   KEYGEN_ARGS+=(-b 4096) ;;
    ecdsa) KEYGEN_ARGS+=(-b 521) ;;
  esac
  # -a makes a stolen key file much harder to crack; very old ssh-keygen versions lack it
  if keygen_has_a_option; then
    KEYGEN_ARGS+=(-a 100)
  fi
  ssh-keygen "${KEYGEN_ARGS[@]}" -f "$KEY" -C "${LOGNAME:-$(id -un)}@$(hostname -s)-$(basename "$KEY")"
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
      # ssh tries these key names on its own; any other key has to be named with -i
      case "$KEY" in
        "$HOME/.ssh/id_ed25519"|"$HOME/.ssh/id_ecdsa"|"$HOME/.ssh/id_rsa") ;;
        *) CONNECT+=" -i ${KEY}" ;;
      esac
      echo "Done. Connect with:  ${CONNECT}"
      ;;
  esac
else
  echo
  echo "Key-based login did not work. Check that the remote sshd allows pubkey auth" >&2
  echo "and that ~/.ssh is 700 and ~/.ssh/authorized_keys is 600 on the remote." >&2
  case "$KEYTYPE" in
    ed25519|ecdsa)
      echo >&2
      echo "If the server is old (OpenSSH before 6.5 for ed25519, 5.7 for ecdsa), it can't use this" >&2
      echo "type of key. Try an RSA key:  $(basename "$0") -t rsa -k NAME ..." >&2
      ;;
    rsa)
      echo >&2
      echo "A very old server (OpenSSH before 7.2) only accepts RSA signatures made with SHA-1," >&2
      echo "which current ssh clients refuse by default. It may need extra, weaker settings such as" >&2
      echo "-o PubkeyAcceptedAlgorithms=+ssh-rsa. This script does not enable those for you." >&2
      ;;
    dsa)
      echo >&2
      echo "This is a DSA key, which current OpenSSH no longer accepts. Create an RSA key with -t rsa." >&2
      ;;
  esac
  exit 1
fi
