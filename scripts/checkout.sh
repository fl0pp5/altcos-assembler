#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mode> <dest-stream>
Prepare stream for work

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mode - OSTree repository mode
    dest-stream - destination ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/nginx\")

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mode" "\$dest_stream"
    exit
fi

stream=$1
repo_root=$2
mode=$3
dest_stream=$4

check_args stream repo_root mode dest_stream
check_stream "$stream" "$repo_root"
check_stream "$dest_stream" "$repo_root"

export_stream "$stream" "$repo_root" "$mode"

base_ostree_dir="$(get_ostree_dir "$stream" "$repo_root" "$mode")"

commit="$(get_commit "$stream" "$repo_root" "$mode" "latest")"

commit_dir="$VARS_DIR"/"$commit"

if [ ! -e "$commit_dir" ]; then
    fatal "directory \"$commit_dir\" does not exists"
    exit 1
fi

export_stream "$dest_stream" "$repo_root" "$mode"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

ostree checkout \
    --repo "$base_ostree_dir" \
    "$commit"
ln -sf "$commit" root

if [[ $(findmnt -M merged) ]]; then
    umount merged
fi

for file in merged upper work; do
    mkdir "$file"
done

mount \
    -t overlay overlay \
    -o lowerdir="$commit",upperdir=upper,workdir=work \
    merged && cd merged

ln -sf usr/etc etc
rsync -a "$commit_dir"/var .

mkdir -p \
    run/lock \
    run/systemd/resolve \
    tmp/.private/root
cp /etc/resolv.conf run/systemd/resolve/resolv.conf
