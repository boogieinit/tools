#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# recent-files.sh - List files created or modified within a recent time window.
#
# Requirements: Linux with Bash, GNU coreutils (date and stat), and GNU find.
# Works on Raspberry Pi OS and other Linux distributions with these tools.
# Creation mode skips files whose filesystem does not report a birth timestamp.
# A scan starting at / skips /proc.
#
# Examples:
#   ./recent-files.sh                    # Created in the last 24 hours here
#   ./recent-files.sh -t 4 /             # Created in the last 4 hours under /
#   ./recent-files.sh -m -t 4 /          # Modified in the last 4 hours under /
#   ./recent-files.sh -c -m -t 4 /       # Modified: -m appears last
#   ./recent-files.sh -m -c -t 4 /       # Created: -c appears last

usage() {
    printf 'Usage: %s [-t HOURS] [-c] [-m] [DIRECTORY]\n' "${0##*/}"
    printf '  -t HOURS  Look back this many whole hours (default: 24)\n'
    printf '  -c        Match by creation time (default)\n'
    printf '  -m        Match by modification time\n'
    printf '  -h        Show this help\n'
    printf '\nIf both -c and -m are given, the last one wins.\n'
}

hours=24
timestamp_format=%W

while getopts ':t:cmh' option; do
    case "$option" in
        t) hours=$OPTARG ;;
        c) timestamp_format=%W ;;
        m) timestamp_format=%Y ;;
        h) usage; exit 0 ;;
        :) printf 'Option -%s requires a value.\n' "$OPTARG" >&2; exit 2 ;;
        \?) printf 'Unknown option -%s.\n' "$OPTARG" >&2; usage >&2; exit 2 ;;
    esac
done
shift "$((OPTIND - 1))"

if [[ ! $hours =~ ^[0-9]{1,9}$ ]] || (( 10#$hours == 0 )); then
    printf 'HOURS must be a positive whole number of up to nine digits.\n' >&2
    exit 2
fi

if (( $# > 1 )); then
    usage >&2
    exit 2
fi

directory=${1:-.}
now=$(date +%s) || exit 1
cutoff=$((now - 10#$hours * 3600))

case "$directory" in
    /*) ;;
    *) directory="./$directory" ;;
esac

find "$directory" -path /proc -prune -o -type f -exec bash -c '
    cutoff=$1
    now=$2
    timestamp_format=$3
    shift 3

    status=0
    for file do
        if ! timestamp=$(stat -c "$timestamp_format" -- "$file"); then
            status=1
            continue
        fi

        # GNU stat returns 0 when creation time is unavailable.
        if [[ $timestamp_format == %W && $timestamp == 0 ]]; then
            continue
        fi

        if (( timestamp >= cutoff && timestamp <= now )); then
            printf "%s\n" "$file"
        fi
    done
    exit "$status"
' bash "$cutoff" "$now" "$timestamp_format" {} +
