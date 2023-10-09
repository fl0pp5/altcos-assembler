#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mkimage-root>
Get rootfs archive via mkimage-profiles

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mkimage-root - mkimage-profiles root

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mkimage_root"
    exit
fi

stream=$1
repo_root=$2
mkimage_root=$3

check_args stream repo_root mkimage_root
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root"

if [ ! -e "$mkimage_root" ]; then
    fatal "directory \"$mkimage_root\" does not exists"
    exit 1
fi

pkg_repo_branch=$(get_apt_repo_branch "$BRANCH")
ns=$(get_apt_repo_namespace "$BRANCH")
apt_arch=$(get_apt_repo_arch "$ARCH")

apt_dir="$HOME"/apt
mkdir -p \
    "$apt_dir"/lists/partial \
    "$apt_dir"/cache/"$BRANCH"/archives/partial \
    "$apt_dir"/"$ARCH"/RPMS.dir

cat <<EOF > "$apt_dir"/apt.conf."$BRANCH"."$ARCH"
Dir::Etc::SourceList $apt_dir/sources.list.$BRANCH.$ARCH;
Dir::Etc::SourceParts /var/empty;
Dir::Etc::main "/dev/null";
Dir::Etc::parts "/var/empty";
APT::Architecture "$apt_arch";
Dir::State::lists $apt_dir/lists;
Dir::Cache $apt_dir/cache/$BRANCH;
EOF


cat <<EOF > "$apt_dir"/sources.list."$BRANCH"."$ARCH"
rpm [$ns] http://ftp.altlinux.org/pub/distributions ALTLinux/$pkg_repo_branch/$ARCH classic
rpm [$ns] http://ftp.altlinux.org/pub/distributions ALTLinux/$pkg_repo_branch/noarch classic
rpm-dir file:$apt_dir $ARCH dir
EOF

cd "$mkimage_root"

make \
    DEBUG=1 \
    APTCONF="$apt_dir"/apt.conf."$BRANCH"."$ARCH" \
    BRANCH="$BRANCH" \
    ARCH="$ARCH" \
    IMAGEDIR="$ROOTFS_DIR" \
    vm/altcos.tar
