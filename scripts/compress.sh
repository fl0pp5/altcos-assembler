#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <commit> <storage> <platform> <format>
compress the image

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    commit - base commit hashsum or \"latest\"
    storage - image storage root
    platform - image platform
    format - image format

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$commit" "\$storage" "\$platform" "\$format"
    exit
fi

stream=$1
repo_root=$2
commit=$3
storage=$4
platform=$5
format=$6

check_args stream repo_root commit storage platform format

check_stream "$stream" "$repo_root"
export_stream "$stream" "$repo_root"

commit="$(get_commit "$stream" "$repo_root" "bare" "$commit")"

version="$(python3 "$__dir"/../stream.py \
    "$stream" \
    "$repo_root" \
    version \
    --commit "$commit")"

build_dir="$(get_artifact_dir \
    "$stream" \
    "$repo_root" \
    "$version" \
    "$platform" \
    "$format" \
    "$storage")"

image_file="$build_dir"/"$BRANCH"_"$NAME"."$ARCH"."$version"."$platform"."$format"

if [ ! -f "$image_file" ]; then
    fatal "\"$image_file\" image file does not exsits"
    exit 1
fi

sudo xz -v9 "$image_file"