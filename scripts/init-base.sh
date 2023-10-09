#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh


# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root>
Initialize the stream repository

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root"
    exit
fi

stream=$1
repo_root=$2

# check incoming data
check_args stream repo_root
check_stream "$stream" "$repo_root"

# export stream's system variables
export_stream "$stream" "$repo_root"


for dir in "$OSTREE_BARE_DIR" "$OSTREE_ARCHIVE_DIR"; do
    if [ -e "$dir" ]; then
        fatal "repository already exists"
        exit 1
    fi

    mkdir -p "$dir"
done

ostree init --repo="$OSTREE_BARE_DIR" --mode=bare
ostree init --repo="$OSTREE_ARCHIVE_DIR" --mode=archive

