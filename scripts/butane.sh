#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <butane>
convert butane to ignition and pass to checkouted repository

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    butane - butane config file

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$butane"
    exit
fi

stream=$1
repo_root=$2
butane=$3

check_args stream repo_root butane
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root"

tmp_butane_file="/tmp/$$.btn"
tmp_ignition_file="/tmp/$$.ign"

echo "$butane" >> "$tmp_butane_file"

butane -p -d \
    "$STREAM_DIR" \
    "$tmp_butane_file" \
| tee "$tmp_ignition_file"

/usr/lib/dracut/modules.d/30ignition/ignition \
    -platform file \
    --stage files \
    -config-cache "$tmp_ignition_file" \
    -root "$MERGED_DIR"

chroot "$MERGED_DIR" \
    systemctl preset-all --preset-mode=enable-only

rm -f \
    "$tmp_butane_file" \
    "$tmp_ignition_file"