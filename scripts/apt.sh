#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <action> [pkgs]...
Package manager wrapper for ALTCOS

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    action - apt-get analogue action (install, remove, update, upgrade)
    pkgs - list of packages

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$action" "\$pkgs"
    exit
fi

stream=$1
repo_root=$2
action=$3

check_args stream repo_root action
check_stream "$stream" "$repo_root"

shift 3
apt_cmd=
pkgs=
case "$action" in
    update)
        apt_cmd="update";;
    upgrade)
        apt_cmd="dist-upgrade";;
    install)
        apt_cmd="install"
        pkgs=$*;;
    remove)
        apt_cmd="remove"
        pkgs=$*;;
    *)
        fatal "invalid apt action \"$action\"" 
        exit 1;;
esac

export_stream "$stream" "$repo_root"

if [ ! -e "$MERGED_DIR" ]; then
    fatal "directory \"$MERGED_DIR\" does not exists ( try to make checkout.sh )"
    exit 1
fi

prepare_apt_dirs "$MERGED_DIR"

# shellcheck disable=SC2086
chroot "$MERGED_DIR" \
    apt-get "$apt_cmd" -y -o RPM::DBPath='lib/rpm' $pkgs
