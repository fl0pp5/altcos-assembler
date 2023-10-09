#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mode> <commit>
ostree pull-local wrapper for ALTCOS

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mode - OSTree repository mode
    commit - base commit hashsum or \"latest\"

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mode" "\$commit"
    exit
fi

stream=$1
repo_root=$2
mode=$3
commit=$4

check_args stream repo_root mode commit
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root" "$mode"

commit="$(get_commit "$stream" "$repo_root" "$mode" "$commit")"

src_ostree_dir="$(get_ostree_dir "$stream" "$repo_root" "$mode")"
if [ "$mode" = "bare" ]; then
    target_ostree_dir="$OSTREE_ARCHIVE_DIR"    
else
    target_ostree_dir="$OSTREE_BARE_DIR"
fi

echo "$src_ostree_dir"
echo "$STREAM"
echo "$commit"

# shellcheck disable=SC2153
ostree pull-local \
    --depth=-1 \
    "$src_ostree_dir" \
    "$STREAM" \
    "$commit" \
    --repo="$target_ostree_dir"

sudo ostree summary --repo="$target_ostree_dir" --update
