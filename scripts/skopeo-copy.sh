#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mode> <images>
copy an docker images to ALTCOS

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mode - OSTree repository mode
    images - list of images to copy

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mode" "\$images"
    exit
fi

stream=$1
repo_root=$2
mode=$3
shift 3
images=$*


check_args stream repo_root mode images
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root" "$mode"

if [ ! -e "$MERGED_DIR" ]; then
    fatal "directory \"$MERGED_DIR\" does not exists."
    exit 1
fi

docker_images_dir="$MERGED_DIR"/usr/dockerImages
mkdir -p "$docker_images_dir"

for image in $images; do
    echo "$image"

    archive_file=$(echo "$image" | tr '/' '_' | tr ':' '_')
    archive_file=$docker_images_dir/$archive_file
    rm -rf "$archive_file"

    xzfile="$archive_file.xz"
    if [ ! -f "$xzfile" ]
    then
        rm -f "$archive_file"
        skopeo copy --additional-tag="$image" docker://"$image" docker-archive:"$archive_file"
        xz -9 "$archive_file"
    fi
done