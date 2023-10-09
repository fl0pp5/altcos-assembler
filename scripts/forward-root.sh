#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <forward-root>
Prepare stream for work

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    forward-root - directory root to forward

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$forward_root"
    exit
fi

stream=$1
repo_root=$2
forward_root=$3

check_args stream repo_root forward_root
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root"

forward_root=$(realpath "$forward_root")

if [ ! -d "$forward_root" ]; then
    fatal "directory \"$forward_root\" does not exists"
    exit 1
fi

cp -r "$forward_root" "$STREAM_DIR"/"$(basename "$forward_root")"
