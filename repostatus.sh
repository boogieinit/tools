#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Show the current branch and local status.

usage() {
    printf 'Usage: %s [-a | -r REPO] [GIT_PARENT_DIRECTORY]\n' "${0##*/}"
    printf '  -a        Process all immediate Git repositories (default)\n'
    printf '  -r REPO   Process one repository by folder name\n'
    printf '  -h        Show this help\n'
    printf 'Default directory: GIT_REPO_ROOT if set, otherwise the current directory.\n'
}

if [[ ${1:-} == --help ]]; then
    usage
    exit 0
fi

repo_name=
while getopts ':ar:h' option; do
    case "$option" in
        a) repo_name= ;;
        r)
            case "$OPTARG" in
                ''|.|..|*/*)
                    printf 'Pass a repository folder name to -r.\n' >&2
                    exit 2
                    ;;
            esac
            repo_name=$OPTARG
            ;;
        h) usage; exit 0 ;;
        :) printf 'Option -%s requires a value.\n' "$OPTARG" >&2; exit 2 ;;
        \?) printf 'Unknown option -%s.\n' "$OPTARG" >&2; usage >&2; exit 2 ;;
    esac
done
shift "$((OPTIND - 1))"

if (( $# > 1 )); then
    usage >&2
    exit 2
fi

repo_root=${1:-${GIT_REPO_ROOT:-.}}
case "$repo_root" in
    /*) ;;
    *) repo_root="./$repo_root" ;;
esac

if ! cd -- "$repo_root"; then
    exit 1
fi

shopt -s nullglob dotglob

exit_status=0
found_repo=0

if [[ -n $repo_name ]]; then
    repos=("$repo_name/")
else
    repos=(*/)
fi

for repo in "${repos[@]}"; do
    [[ -d "${repo}.git" || -f "${repo}.git" ]] || continue
    found_repo=1

    printf '\n=== %s ===\n' "${repo%/}"
    git -C "./$repo" status --short --branch || exit_status=1
done

if (( found_repo == 0 )); then
    if [[ -n $repo_name ]]; then
        printf 'Git repository "%s" not found in "%s".\n' "$repo_name" "$PWD" >&2
        exit 1
    fi
    printf 'No Git repositories found in "%s".\n' "$PWD"
fi

exit "$exit_status"
