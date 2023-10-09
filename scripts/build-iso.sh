#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mode> <storage> <commit> <mkimage-root>
Build qcow2 image

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mode - OSTree repository mode
    storage - image storage root
    commit - base commit hashsum or \"latest\"
    mkimage-root - mkimage-profiles root

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mode" "\$storage" "\$commit" "\$mkimage_root"
    exit
fi

stream=$1
repo_root=$2
mode=$3
storage=$4
commit=$5
mkimage_root=$6

platform=metal
format=iso

apt_dir="$HOME"/apt

check_args stream repo_root mode storage commit
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root" "$mode"

commit="$(get_commit "$stream" "$repo_root" "$mode" "$commit" "$mkimage_root")"

version="$(python3 "$__dir"/../stream.py \
    "$stream" \
    "$repo_root" \
    --mode "$mode" \
    version \
    --commit "$commit")"

version_path="$(python3 "$__dir"/../stream.py \
    "$stream" \
    "$repo_root" \
    --mode "$mode" \
    version \
    --commit "$commit" \
    --view path)"

commit_dir="$VARS_DIR"/"$version_path"/var

build_dir="$(get_artifact_dir \
    "$stream" \
    "$repo_root" \
    "$version" \
    "$platform" \
    "$format" \
    "$storage")"

sudo mkdir -p "$build_dir"
sudo chmod -R 777 "$build_dir"

image_file="$build_dir"/"$BRANCH"_"$NAME"."$ARCH"."$version"."$platform"."$format"

rpmbuild_dir="$(mktemp --tmpdir -d "$(basename "$0")"_rpmbuild-XXXXXX)"
mkdir "$rpmbuild_dir"/SOURCES

cur_dir="$(pwd)"
cd "$__dir"/specs/startup-installer-altcos
# shellcheck disable=SC2153
gear-rpm \
    -bb \
    --define "stream $STREAM" \
    --define "_rpmdir $apt_dir/$ARCH/RPMS.dir/" \
    --define "_rpmfilename startup-installer-altcos-0.2.4-alt1.x86_64.rpm"
cd "$cur_dir"

sudo tar -cf - \
    -C "$(dirname "$commit_dir")" var \
    | xz -9 -c - > "$rpmbuild_dir"/SOURCES/var.tar.xz

mkdir "$rpmbuild_dir"/altcos_root

ostree admin init-fs \
    --modern "$rpmbuild_dir"/altcos_root

ostree_dir="$(get_ostree_dir "$stream" "$repo_root" "$mode")"
sudo ostree \
    pull-local \
    --repo "$rpmbuild_dir"/altcos_root/ostree/repo \
    "$ostree_dir" \
    "$STREAM"

sudo tar -cf - -C "$rpmbuild_dir"/altcos_root . \
    | xz -9 -c -T0 - > "$rpmbuild_dir"/SOURCES/altcos_root.tar.xz
sudo rm -rf "$rpmbuild_dir"/altcos_root

rpmbuild \
    --define "_topdir $rpmbuild_dir" \
    --define "_rpmdir $apt_dir/$ARCH/RPMS.dir/" \
    --define "_rpmfilename altcos-archives-0.1-alt1.x86_64.rpm" \
    -bb "$__dir"/specs/altcos-archives.spec

sudo rm -rf "$rpmbuild_dir"

sudo chmod a+w "$build_dir"

make \
    -C "$mkimage_root" \
    APTCONF="$apt_dir"/apt.conf."$BRANCH"."$ARCH" \
    BRANCH="$BRANCH" \
    IMAGEDIR="$build_dir" \
    live-altcos-install.iso

mv "$(realpath "$build_dir"/live-altcos-install-latest-x86_64.iso)" "$image_file"

find "$build_dir" -type l -delete

echo "$image_file"
