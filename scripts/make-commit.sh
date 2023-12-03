#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mode> <commit> <next> <message>
Sync reference with base commit and commits the new version

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mode - OSTree repository mode
    commit - base commit hashsum or \"latest\"
    next - next version part increment (major|minor)
    message - commit message

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mode" "\$commit" "\$next" "\$message"
    exit
fi

stream=$1
repo_root=$2
mode=$3
commit=$4
next=$5
message=$6

check_args stream repo_root mode commit next message
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root" "$mode"

if [ ! -e "$MERGED_DIR" ]; then
    fatal "directory \"$MERGED_DIR\" does not exists ( try to make checkout.sh )"
    exit 1
fi

guess_commit="$(get_commit "$stream" "$repo_root" "$mode" "$commit")"
if [ -z "$guess_commit" ]; then
    # if the commit does not exist yet, let's take the parent branch as a basis
    guess_commit="$(get_commit altcos/"$ARCH"/"$BRANCH"/base "$repo_root" "$mode" "$commit")"
    # in order for the substream version starts from <date>.0.0, need to remove the base stream commit from the argumets
    version_get_args="$stream $repo_root --mode $mode version --next $next"
else
    version_get_args="$stream $repo_root --mode $mode version --commit $guess_commit --next $next"
fi
commit="$guess_commit"

# shellcheck disable=SC2086
version="$(python3 "$__dir"/../stream.py \
    $version_get_args \
    --view full)"

# shellcheck disable=SC2086
version_path="$(python3 "$__dir"/../stream.py \
    $version_get_args \
    --view path)"

var_dir="$VARS_DIR"/"$version_path"

cd "$WORK_DIR"
rm -f upper/etc root/etc

mkdir -p "$var_dir"

cd upper
mkdir -p var/lib/apt var/cache/apt

prepare_apt_dirs "$PWD"

rsync -av var "$var_dir"

rm -rf run var
mkdir var

to_delete=$(find . -type c)
cd "$WORK_DIR"/root
rm -rf "$to_delete"

cd ../upper

set +eo pipefail 
find . -depth | (cd ../merged;cpio -pmdu "$WORK_DIR"/root)
set -eo pipefail

cd ..
umount merged

set +eo pipefail

add_metadata=
out="$(is_base_stream "$NAME")"
if [ "$out" = "no" ]; then
    add_metadata=" --add-metadata-string=parent_commit_id=$commit"
    add_metadata="$add_metadata --add-metadata-string=parent_version=$version"
fi

set -eo pipefail

ostree_dir="$(get_ostree_dir "$stream" "$repo_root" "$mode")"

# shellcheck disable=SC2153
new_commit=$(
    ostree commit \
        --repo="$ostree_dir" \
        --tree=dir="$commit" \
        -b "$STREAM" \
        -m "$message" \
        --no-bindings \
        --mode-ro-executables \
        "$add_metadata" \
        --add-metadata-string=version="$version")

cd "$VARS_DIR"
ln -sf "$version_path" "$new_commit"
rm -rf "$commit"

ostree summary --repo="$ostree_dir" --update

rm -rf "$WORK_DIR"

echo "$new_commit" 