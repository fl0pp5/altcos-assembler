#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mode> <storage> <commit>
Build qcow2 image

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mode - OSTree repository mode
    storage - image storage root
    commit - base commit hashsum or \"latest\"

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mode" "\$storage" "\$commit"
    exit
fi

stream=$1
repo_root=$2
mode=$3
storage=$4
commit=$5

platform=qemu
format=qcow2

root_size=4G

efi_support=0
if efibootmgr; then
    efi_support=1
fi

check_args stream repo_root mode storage commit
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root" "$mode"

commit="$(get_commit "$stream" "$repo_root" "$mode" "$commit")"

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

mkdir -p "$build_dir"

image_file="$build_dir"/"$BRANCH"_"$NAME"."$ARCH"."$version"."$platform"."$format"

mount_dir=$(mktemp --tmpdir -d "$(basename "$0")"-XXXXXX)

raw_file=$(mktemp --tmpdir "$(basename "$0")"-XXXXXX.raw)

mount_dir_repo="$mount_dir/ostree/repo"
mount_dir_efi="$mount_dir/boot/efi"

fallocate -l "$root_size" "$raw_file"

loop_dev=$(losetup --show -f "$raw_file")
efi_part="$loop_dev"p1
root_part="$loop_dev"p3

parted "$loop_dev" mktable gpt
parted -a optimal "$loop_dev" mkpart primary fat32 1MIB 256MIB
parted -a optimal "$loop_dev" mkpart primary fat32 256MIB 257MIB
parted -a optimal "$loop_dev" mkpart primary ext4 257MIB 100%

mkfs.fat -F32 "$efi_part"
mkfs.ext4 -L boot "$root_part"

# ef02 - BIOS
# 8304 - root
sgdisk \
    --typecode 2:ef02 \
    --typecode 3:8304 \
    --change-name 3:boot \
    --change-name 1:EFI \
    "$loop_dev"
partprobe "$loop_dev"

mount "$root_part" "$mount_dir"
mkdir -p "$mount_dir_efi"
mount "$efi_part"  "$mount_dir_efi"

ostree admin \
    init-fs \
    --modern "$mount_dir"

ostree_dir="$(get_ostree_dir "$stream" "$repo_root" "$mode")"

ostree pull-local \
    --repo "$mount_dir_repo" \
    "$ostree_dir" \
    "$commit"

grub-install \
    --target=i386-pc \
    --root-directory="$mount_dir" \
    "$loop_dev"

if [ "$efi_support" -eq 1 ]; then
    grub-install \
        --target=x86_64-efi \
        --root-directory="$mount_dir" \
        --efi-directory="$mount_dir_efi"
fi

ln -s ../loader/grub.cfg "$mount_dir"/boot/grub/grub.cfg

ostree config \
    --repo "$mount_dir_repo" \
    set sysroot.bootloader grub2

ostree config \
    --repo "$mount_dir_repo" \
    set sysroot.readonly true

# shellcheck disable=SC2153
ostree refs \
    --repo "$mount_dir_repo" \
    --create altcos:"$STREAM" \
    "$commit"

ostree admin \
    os-init "$OSNAME" \
    --sysroot "$mount_dir"

OSTREE_BOOT_PARTITION="/boot" ostree admin deploy altcos:"$STREAM" \
    --sysroot "$mount_dir" \
    --os "$OSNAME" \
    --karg-append=ignition.platform.id=qemu \
    --karg-append=\$ignition_firstboot \
    --karg-append=net.ifnames=0 \
    --karg-append=biosdevname=0 \
    --karg-append=rw \
    --karg-append=quiet \
    --karg-append=root=UUID="$(blkid --match-tag UUID -o value "$root_part")"

rm -rf "$mount_dir"/ostree/deploy/"$OSNAME"/var

rsync -av "$commit_dir" \
        "$mount_dir"/ostree/deploy/"$OSNAME"

touch "$mount_dir"/ostree/deploy/"$OSNAME"/var/.ostree-selabeled
touch "$mount_dir"/boot/ignition.firstboot

if [ "$efi_support" -eq 1 ]; then
    mkdir -p "$mount_dir_efi"/EFI/BOOT
    mv "$mount_dir_efi"/EFI/altlinux/shimx64.efi "$mount_dir_efi"/EFI/BOOT/bootx64.efi
    mv "$mount_dir_efi"/EFI/altlinux/{grubx64.efi,grub.cfg} "$mount_dir_efi"/EFI/BOOT/
fi

echo "UUID=$(blkid --match-tag UUID -o value "$efi_part") /boot/efi vfat umask=0,quiet,showexec,iocharset=utf8,codepage=866 1 2" \
    >> "$mount_dir"/ostree/deploy/"$OSNAME"/deploy/"$commit".0/etc/fstab

umount -R "$mount_dir"
rm -rf "$mount_dir"
losetup -d "$loop_dev"

qemu-img convert -O qcow2 "$raw_file" "$image_file"
rm "$raw_file"

echo "$image_file"