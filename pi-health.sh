#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# pi-health.sh - Raspberry Pi 5 health check with optional e-mail alerting.
#
# Checks: CPU temp, throttling / under-voltage, fan, load, memory, swap,
#         disk space, inodes, read-only filesystems, failed systemd units,
#         clock sync, network reachability, kernel errors, unexpected reboots,
#         and NVMe SMART health (only when run as root with smartctl).
#
# Exit code: 0 = all OK, 1 = warning(s), 2 = critical.
#
# Examples:
#   pi-health.sh                      # full report to the terminal
#   pi-health.sh -q                   # print nothing unless there is a problem
#   pi-health.sh -q -m me@example.com # e-mail only when something is wrong
#   WARN_TEMP=65 pi-health.sh -m me@example.com   # override a threshold
#
# Cron (hourly):
#   0 * * * * /usr/local/bin/pi-health.sh -q -m me@example.com -l /var/log/pi-health.log >/dev/null 2>&1

set -u
export LC_ALL=C
PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

VERSION="1.0"

# ----------------------------------------------------------------- thresholds
# Override with environment variables or a config file (-c FILE).
# Pi 5 soft-throttles at 80C and hard-throttles at 85C.
: "${WARN_TEMP:=70}"      "${CRIT_TEMP:=80}"      # CPU temperature, C
: "${WARN_DISK:=80}"      "${CRIT_DISK:=90}"      # filesystem used, %
: "${WARN_INODE:=80}"     "${CRIT_INODE:=90}"     # inodes used, %
: "${WARN_MEM:=85}"       "${CRIT_MEM:=95}"       # memory used (excl. cache), %
: "${WARN_SWAP:=50}"      "${CRIT_SWAP:=80}"      # swap used, %
: "${WARN_LOAD:=1.0}"     "${CRIT_LOAD:=2.0}"     # 15-min load per CPU core
: "${FAN_CHECK_TEMP:=60}"                         # fan at 0 rpm above this temp = problem
: "${REBOOT_WINDOW_MIN:=75}"                      # warn if up for less than this (hourly cron)
: "${LOG_WINDOW:=1 hour ago}"                     # how far back to scan the kernel log
: "${PING_HOST:=1.1.1.1}"                         # network reachability target
: "${KERNEL_PATTERNS:=Under-voltage detected|I/O error|EXT4-fs error|mmc[0-9]+.*(error|timeout)|nvme.*(timeout|reset|error)|Out of memory|oom-kill|Call trace|Buffer I/O}"

# --------------------------------------------------------------------- options
MAIL_TO=""
MAIL_FROM=""
REPEAT_HOURS=12      # re-send a still-active alert after this many hours (0 = every run)
ALERT_LEVEL=1        # 1 = e-mail on WARN and CRIT, 2 = CRIT only
QUIET=0
FORCE_MAIL=0
TEST_MAIL=0
CHECK_NET=1
LOG_FILE=""
CONFIG=""
STATE_DIR="${PI_HEALTH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/pi-health}"

usage() {
  cat <<EOF
pi-health.sh $VERSION - Raspberry Pi health check

Usage: ${0##*/} [options]

  -m, --mail ADDR       E-mail ADDR when problems are found (and when they clear).
  -f, --from ADDR       Optional From: address for the e-mail.
  -r, --repeat HOURS    Re-send a still-active alert every HOURS (default $REPEAT_HOURS, 0 = every run).
      --crit-only       Only e-mail for critical problems, not warnings.
      --force-mail      Send the e-mail now regardless of state (shows the full report).
      --test-mail       Send a test e-mail to verify mail delivery, then exit.
  -q, --quiet           Print nothing when everything is healthy.
  -l, --log FILE        Append a one-line summary of every run to FILE (for trend history).
  -c, --config FILE     Source FILE for threshold overrides (plain shell VAR=value lines).
      --ping-host HOST  Host to ping for the network check (default $PING_HOST).
      --no-net          Skip the network check.
  -h, --help            Show this help.

Thresholds (override via environment or config file):
  WARN_TEMP/CRIT_TEMP  WARN_DISK/CRIT_DISK  WARN_INODE/CRIT_INODE
  WARN_MEM/CRIT_MEM    WARN_SWAP/CRIT_SWAP  WARN_LOAD/CRIT_LOAD (per core, 15-min avg)

Exit status: 0 = OK, 1 = warning, 2 = critical.
EOF
}

die() { printf 'pi-health: %s\n' "$*" >&2; exit 3; }

while (( $# )); do
  case $1 in
    -m|--mail)       [[ $# -ge 2 ]] || die "$1 needs an argument"; MAIL_TO=$2; shift ;;
    -f|--from)       [[ $# -ge 2 ]] || die "$1 needs an argument"; MAIL_FROM=$2; shift ;;
    -r|--repeat)     [[ ${2:-} =~ ^[0-9]+$ ]] || die "$1 needs a whole number of hours"; REPEAT_HOURS=$2; shift ;;
    --crit-only)     ALERT_LEVEL=2 ;;
    --force-mail)    FORCE_MAIL=1 ;;
    --test-mail)     TEST_MAIL=1 ;;
    -q|--quiet)      QUIET=1 ;;
    -l|--log)        [[ $# -ge 2 ]] || die "$1 needs an argument"; LOG_FILE=$2; shift ;;
    -c|--config)     [[ $# -ge 2 ]] || die "$1 needs an argument"; CONFIG=$2; shift ;;
    --ping-host)     [[ $# -ge 2 ]] || die "$1 needs an argument"; PING_HOST=$2; shift ;;
    --no-net)        CHECK_NET=0 ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

if [[ -n $CONFIG ]]; then
  [[ -r $CONFIG ]] || die "cannot read config file: $CONFIG"
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

HOST=$(hostname)
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------- e-mail
send_mail() {  # subject body
  local subject=$1 body=$2
  [[ -n $MAIL_TO ]] || return 1
  if have msmtp || have sendmail; then
    local sender; sender=$(have msmtp && echo msmtp || echo sendmail)
    {
      printf 'To: %s\n' "$MAIL_TO"
      [[ -n $MAIL_FROM ]] && printf 'From: %s\n' "$MAIL_FROM"
      printf 'Subject: %s\n' "$subject"
      printf 'Content-Type: text/plain; charset=UTF-8\n\n'
      printf '%s\n' "$body"
    } | "$sender" -t
  elif have mail || have mailx; then
    local m; m=$(have mail && echo mail || echo mailx)
    if [[ -n $MAIL_FROM ]]; then
      printf '%s\n' "$body" | "$m" -s "$subject" -r "$MAIL_FROM" "$MAIL_TO"
    else
      printf '%s\n' "$body" | "$m" -s "$subject" "$MAIL_TO"
    fi
  else
    printf 'pi-health: no mail program found (install msmtp-mta, postfix, or bsd-mailx)\n' >&2
    return 1
  fi
}

if (( TEST_MAIL )); then
  [[ -n $MAIL_TO ]] || die "--test-mail needs -m ADDRESS"
  if send_mail "[pi-health] test message from $HOST" "If you can read this, e-mail alerts from $HOST work."; then
    echo "Test e-mail sent to $MAIL_TO"; exit 0
  fi
  die "test e-mail failed"
fi

# -------------------------------------------------------------------- helpers
WORST=0
declare -a REPORT=() PROBLEMS=() SIG=()

# record LEVEL LABEL MESSAGE   (LEVEL: 0 ok, 1 warn, 2 crit)
record() {
  local lvl=$1 label=$2 msg=$3 tag line
  case $lvl in 0) tag="OK  " ;; 1) tag="WARN" ;; *) tag="CRIT" ;; esac
  line="[$tag] $label: $msg"
  REPORT+=("$line")
  if (( lvl > 0 )); then PROBLEMS+=("$line"); fi
  if (( lvl >= ALERT_LEVEL )); then SIG+=("$lvl $label"); fi
  if (( lvl > WORST )); then WORST=$lvl; fi
}

# level_for VALUE WARN CRIT -> prints 0/1/2
level_for() {
  awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN { if (v+0 >= c+0) print 2; else if (v+0 >= w+0) print 1; else print 0 }'
}

TEMP="" LOAD15="" MEMPCT="" ROOTPCT=""

# --------------------------------------------------------------------- checks
check_temp() {
  local t=""
  if have vcgencmd; then
    t=$(vcgencmd measure_temp 2>/dev/null); t=${t#temp=}; t=${t%\'C}
  fi
  if ! [[ $t =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    t=$(awk '{ printf "%.1f", $1 / 1000 }' /sys/class/thermal/thermal_zone0/temp)
  fi
  [[ $t =~ ^[0-9]+(\.[0-9]+)?$ ]] || { record 1 "CPU temp" "could not read temperature"; return; }
  TEMP=$t
  record "$(level_for "$t" "$WARN_TEMP" "$CRIT_TEMP")" "CPU temp" "${t}C (warn ${WARN_TEMP}, crit ${CRIT_TEMP})"
}

check_throttle() {
  have vcgencmd || return
  local raw hex val
  raw=$(vcgencmd get_throttled 2>/dev/null) || return
  hex=${raw#throttled=}
  [[ $hex =~ ^0x[0-9a-fA-F]+$ ]] || return
  val=$(( hex ))
  local now=() past=()
  (( val & 0x1 ))     && now+=("under-voltage")
  (( val & 0x2 ))     && now+=("ARM frequency capped")
  (( val & 0x4 ))     && now+=("throttled")
  (( val & 0x8 ))     && now+=("soft temp limit")
  (( val & 0x10000 )) && past+=("under-voltage")
  (( val & 0x20000 )) && past+=("frequency capped")
  (( val & 0x40000 )) && past+=("throttled")
  (( val & 0x80000 )) && past+=("soft temp limit")
  local IFS=,
  if (( ${#now[@]} )); then
    record 2 "Throttling" "active now: ${now[*]} (flags $hex) - check PSU (5V/5A) and cooling"
  elif (( ${#past[@]} )); then
    record 1 "Throttling" "occurred since boot: ${past[*]} (flags $hex)"
  else
    record 0 "Throttling" "none since boot"
  fi
}

check_fan() {
  local f rpm found=0
  for f in /sys/class/hwmon/hwmon*/fan1_input; do
    [[ -r $f ]] || continue
    found=1; rpm=$(<"$f")
    [[ $rpm =~ ^[0-9]+$ ]] || continue
    if (( rpm == 0 )) && [[ -n $TEMP ]] && awk -v t="$TEMP" -v l="$FAN_CHECK_TEMP" 'BEGIN { exit !(t+0 > l+0) }'; then
      record 2 "Fan" "0 rpm while CPU is ${TEMP}C - fan stopped or disconnected"
    else
      record 0 "Fan" "${rpm} rpm"
    fi
    return
  done
  (( found )) || true   # no fan sensor (no Active Cooler fitted) - nothing to report
}

check_load() {
  local cores l1 l5 l15 per
  cores=$(nproc 2>/dev/null || echo 1)
  read -r l1 l5 l15 _ < /proc/loadavg
  LOAD15=$l15
  per=$(awk -v l="$l15" -v c="$cores" 'BEGIN { printf "%.2f", l / c }')
  record "$(level_for "$per" "$WARN_LOAD" "$CRIT_LOAD")" "Load" \
    "${l1} ${l5} ${l15} (1/5/15 min), ${per} per core over ${cores} cores (warn ${WARN_LOAD}, crit ${CRIT_LOAD})"
}

check_memory() {
  local total avail stotal sfree used swapused
  total=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
  avail=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  stotal=$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)
  sfree=$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)
  [[ -n $total && -n $avail ]] || return
  used=$(awk -v t="$total" -v a="$avail" 'BEGIN { printf "%.0f", (t - a) * 100 / t }')
  MEMPCT=$used
  record "$(level_for "$used" "$WARN_MEM" "$CRIT_MEM")" "Memory" \
    "${used}% used of $(( total / 1024 )) MB (warn ${WARN_MEM}, crit ${CRIT_MEM})"
  if [[ -n $stotal ]] && (( stotal > 0 )); then
    swapused=$(awk -v t="$stotal" -v f="$sfree" 'BEGIN { printf "%.0f", (t - f) * 100 / t }')
    record "$(level_for "$swapused" "$WARN_SWAP" "$CRIT_SWAP")" "Swap" \
      "${swapused}% used of $(( stotal / 1024 )) MB (warn ${WARN_SWAP}, crit ${CRIT_SWAP})"
  fi
}

DF_EXCLUDES=(-x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x fuse.gvfsd-fuse -x iso9660)

check_disk() {
  local pct mount
  while read -r pct mount; do
    pct=${pct%\%}
    [[ $pct =~ ^[0-9]+$ ]] || continue
    [[ $mount == / ]] && ROOTPCT=$pct
    record "$(level_for "$pct" "$WARN_DISK" "$CRIT_DISK")" "Disk $mount" \
      "${pct}% used (warn ${WARN_DISK}, crit ${CRIT_DISK})"
  done < <(df -P "${DF_EXCLUDES[@]}" 2>/dev/null | awk 'NR > 1 { print $5, $6 }')
}

check_inodes() {
  local pct mount
  while read -r pct mount; do
    pct=${pct%\%}
    [[ $pct =~ ^[0-9]+$ ]] || continue     # vfat etc. report "-"
    local lvl; lvl=$(level_for "$pct" "$WARN_INODE" "$CRIT_INODE")
    (( lvl > 0 )) && record "$lvl" "Inodes $mount" "${pct}% used (warn ${WARN_INODE}, crit ${CRIT_INODE})"
  done < <(df -Pi "${DF_EXCLUDES[@]}" 2>/dev/null | awk 'NR > 1 { print $5, $6 }')
}

check_readonly() {
  local ro
  ro=$(awk '$3 ~ /^(ext[234]|f2fs|xfs|btrfs)$/ && $4 ~ /(^|,)ro(,|$)/ { printf "%s ", $2 }' /proc/mounts)
  if [[ -n $ro ]]; then
    record 2 "Filesystems" "mounted READ-ONLY: ${ro}(SD/NVMe errors or corruption?)"
  else
    record 0 "Filesystems" "all writable"
  fi
}

check_units() {
  have systemctl || return
  local failed n
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{ print $1 }')
  if [[ -n $failed ]]; then
    n=$(printf '%s\n' "$failed" | wc -l)
    record 1 "systemd" "${n} failed unit(s): $(printf '%s' "$failed" | tr '\n' ' ')"
  else
    record 0 "systemd" "no failed units"
  fi
}

check_time() {
  have timedatectl || return
  local s; s=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
  case $s in
    yes) record 0 "Clock" "NTP synchronised" ;;
    no)  record 1 "Clock" "NTP not synchronised" ;;
  esac
}

check_network() {
  (( CHECK_NET )) && have ping || return
  if ping -c 1 -W 3 "$PING_HOST" >/dev/null 2>&1; then
    record 0 "Network" "$PING_HOST reachable"
  else
    record 2 "Network" "$PING_HOST unreachable"
  fi
}

check_kernel_log() {
  have journalctl || return
  local out n
  out=$(journalctl -k --since "$LOG_WINDOW" --no-pager -q 2>/dev/null | grep -Ei "$KERNEL_PATTERNS" | grep -v 'Voltage normalised')
  [[ -n $out ]] || { journalctl -k -n 1 --no-pager -q >/dev/null 2>&1 && record 0 "Kernel log" "no errors since ${LOG_WINDOW}"; return; }
  n=$(printf '%s\n' "$out" | wc -l)
  record 1 "Kernel log" "${n} suspicious message(s) in window; latest: $(printf '%s' "$out" | tail -n 1 | cut -c1-160)"
}

check_uptime() {
  local up; up=$(cut -d. -f1 /proc/uptime)
  if (( up < REBOOT_WINDOW_MIN * 60 )); then
    record 1 "Uptime" "rebooted $(( up / 60 )) min ago (power loss or crash?)"
  else
    record 0 "Uptime" "$(( up / 86400 ))d $(( up % 86400 / 3600 ))h"
  fi
}

check_nvme() {
  (( EUID == 0 )) && have smartctl || return
  local dev
  for dev in /dev/nvme[0-9]n1; do
    [[ -e $dev ]] || continue
    if smartctl -H "$dev" 2>/dev/null | grep -qi 'PASSED'; then
      record 0 "NVMe $dev" "SMART health PASSED"
    else
      record 2 "NVMe $dev" "SMART health check did NOT pass"
    fi
  done
}

# ------------------------------------------------------------------- run them
check_temp
check_throttle
check_fan
check_load
check_memory
check_disk
check_inodes
check_readonly
check_units
check_time
check_network
check_kernel_log
check_uptime
check_nvme

case $WORST in 0) STATUS="OK" ;; 1) STATUS="WARNING" ;; *) STATUS="CRITICAL" ;; esac

# --------------------------------------------------------------------- report
build_report() {
  local model=""
  [[ -r /proc/device-tree/model ]] && model=$(tr -d '\0' < /proc/device-tree/model)
  printf 'Host:    %s%s\n' "$HOST" "${model:+ ($model)}"
  printf 'Time:    %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf 'Status:  %s\n\n' "$STATUS"
  printf '%s\n' "${REPORT[@]}"
  if (( WORST > 0 )); then
    printf '\nTop CPU processes:\n'
    ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -n 6
    printf '\nTop memory processes:\n'
    ps -eo pid,pcpu,pmem,comm --sort=-pmem 2>/dev/null | head -n 6
  fi
}

REPORT_TEXT=$(build_report)

if (( ! QUIET )) || (( WORST > 0 )); then
  printf '%s\n' "$REPORT_TEXT"
fi

if [[ -n $LOG_FILE ]]; then
  printf '%s status=%s temp=%s load15=%s mem=%s%% root=%s%% problems=%d\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S')" "$STATUS" "${TEMP:-?}" "${LOAD15:-?}" "${MEMPCT:-?}" "${ROOTPCT:-?}" "${#PROBLEMS[@]}" \
    >> "$LOG_FILE" 2>/dev/null || printf 'pi-health: cannot write log %s\n' "$LOG_FILE" >&2
fi

# ----------------------------------------------------------- alert e-mailing
# Sends when the SET of problems changes, when a problem has persisted longer
# than --repeat hours, and once more when everything returns to normal.
maybe_mail() {
  [[ -n $MAIL_TO ]] || return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || { printf 'pi-health: cannot create %s\n' "$STATE_DIR" >&2; return 0; }
  local state_file="$STATE_DIR/last-alert" prev_sig="" prev_ts=0 now sig subject
  now=$(date +%s)
  [[ -r $state_file ]] && read -r prev_sig prev_ts < "$state_file"
  [[ $prev_ts =~ ^[0-9]+$ ]] || prev_ts=0

  if (( ${#SIG[@]} )); then
    sig=$(printf '%s\n' "${SIG[@]}" | sort | cksum | cut -d' ' -f1)
    local due=0
    (( FORCE_MAIL )) && due=1
    [[ $sig != "$prev_sig" ]] && due=1
    (( REPEAT_HOURS == 0 )) && due=1
    (( REPEAT_HOURS > 0 && now - prev_ts >= REPEAT_HOURS * 3600 )) && due=1
    if (( due )); then
      local worst_tag="WARNING"; for s in "${SIG[@]}"; do [[ $s == 2* ]] && worst_tag="CRITICAL"; done
      subject="[pi-health] $worst_tag on $HOST: $(printf '%s\n' "${PROBLEMS[@]}" | sed -E 's/^\[[A-Z ]+\] //; s/ \(.*//' | head -n 3 | paste -sd';' | cut -c1-120)"
      if send_mail "$subject" "$REPORT_TEXT"; then
        printf '%s %s\n' "$sig" "$now" > "$state_file"
      else
        printf 'pi-health: failed to send alert e-mail\n' >&2
      fi
    fi
  else
    if [[ -n $prev_sig ]] || (( FORCE_MAIL )); then
      if send_mail "[pi-health] RECOVERED on $HOST: all checks OK" "$REPORT_TEXT"; then
        : > "$state_file"
      else
        printf 'pi-health: failed to send recovery e-mail\n' >&2
      fi
    fi
  fi
}

maybe_mail
exit "$WORST"
