#!/usr/bin/env bash

set -eo pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/utils.sh

check_root_uid

# shellcheck disable=SC2034
usage="Usage: $__name [options] <stream> <repo-root> <mode> <url> <message>
Convert the rootfs archive to OSTree repository

Arguments:
    stream - ALTCOS repository stream (e.g. \"altcos/x86_64/sisyphus/base\")
    repo-root - ALTCOS repository root
    mode - OSTree repository mode
    url - ALTCOS update server address
    message - commit message

    Options:
        -a, --api - print API-like arguments (e.g. \"\$stream \$repo-root\")
        -h, --help - print this message"


need_api=0
handle_options "$@"
if [ "$need_api" -eq 1 ]; then
    echo -n "\$stream" "\$repo_root" "\$mode" "\$url" "\$message"
    exit
fi

stream=$1
repo_root=$2
mode=$3
url=$4
message=$5

check_args stream repo_root mode url message
check_stream "$stream" "$repo_root"

export_stream "$stream" "$repo_root" "$mode"

output="$(is_base_stream "$NAME")"
if [ "$output" = "no" ]; then
    fatal "only the base stream allowed"
    exit 1
fi

ostree_dir="$(get_ostree_dir "$stream" "$repo_root" "$mode")"

tmpdir="$(mktemp --tmpdir -d "$(basename "$0")"-XXXXXX)"
root_tmpdir="$tmpdir"/root
mkdir -p "$root_tmpdir"

tar xf "$ROOTFS_ARCHIVE" -C "$root_tmpdir" \
    --exclude=./dev/tty \
    --exclude=./dev/tty0 \
    --exclude=./dev/console \
    --exclude=./dev/urandom \
    --exclude=./dev/random \
    --exclude=./dev/full \
    --exclude=./dev/zero \
    --exclude=./dev/pts/ptmx \
    --exclude=./dev/null

rm -f "$root_tmpdir"/etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf "$root_tmpdir"/etc/resolv.conf

ns=$(get_apt_repo_namespace "$BRANCH")

sed -i "s/#rpm \[$ns\] http/rpm \[$ns\] http/" "$root_tmpdir"/etc/apt/sources.list.d/alt.list
sed -i 's/^LABEL=ROOT\t/LABEL=boot\t/g' "$root_tmpdir"/etc/fstab
sed -i 's/^AcceptEnv /#AcceptEnv /g' "$root_tmpdir"/etc/openssh/sshd_config
sed -i 's/^# WHEEL_USERS ALL=(ALL) ALL$/WHEEL_USERS ALL=(ALL) ALL/g' "$root_tmpdir"/etc/sudoers
echo "zincati ALL=NOPASSWD: ALL" > "$root_tmpdir"/etc/sudoers.d/zincati
sed -i 's|^HOME=/home$|HOME=/var/home|g' "$root_tmpdir"/etc/default/useradd
echo "blacklist floppy" > "$root_tmpdir"/etc/modprobe.d/blacklist-floppy.conf

mkdir -m 0775 "$root_tmpdir"/sysroot
ln -s sysroot/ostree "$root_tmpdir"/ostree

for dir in home opt srv mnt; do
    mv -f "$root_tmpdir"/"$dir" "$root_tmpdir"/var
    ln -sf var/"$dir" "$root_tmpdir"/"$dir"
done

mv -f "$root_tmpdir"/root "$root_tmpdir/var/roothome"
mv -f "$root_tmpdir"/usr/local "$root_tmpdir/var/usrlocal"
ln -sf var/roothome "$root_tmpdir"/root
ln -sf ../var/usrlocal "$root_tmpdir"/usr/local

mkdir -p "$root_tmpdir"/etc/ostree/remotes.d
echo "
[remote \"altcos\"]
url=$url/streams/$BRANCH/$ARCH/ostree/archive
gpg-verify=false
" > "$root_tmpdir"/etc/ostree/remotes.d/altcos.conf

echo "
# ALTLinux CoreOS Cincinnati backend
[cincinnati]
base_url=\"$url\"
" > "$root_tmpdir"/etc/zincati/config.d/50-altcos-cincinnati.toml


echo "
[Match]
Name=eth0

[Network]
DHCP=yes
" > "$root_tmpdir"/etc/systemd/network/20-wired.network

sed -i -e 's|#AuthorizedKeysFile\(.*\)|AuthorizedKeysFile\1 .ssh/authorized_keys.d/ignition|' \
    "$root_tmpdir"/etc/openssh/sshd_config

chroot "$root_tmpdir" groupadd altcos

# shellcheck disable=SC2016 
chroot "$root_tmpdir" useradd \
    -g altcos \
    -G docker,wheel \
    -d /var/home/altcos \
    --create-home \
    -s /bin/bash altcos \
    -p '$y$j9T$ZEYmKSGPiNFOZNTjvobEm1$IXLGt5TxdNC/OhJyzFK5NVM.mt6VvdtP6mhhzSmvE94' # password: 1

split_passwd "$root_tmpdir"/etc/passwd "$root_tmpdir"/lib/passwd /tmp/passwd.$$
mv /tmp/passwd.$$ "$root_tmpdir"/etc/passwd

split_group "$root_tmpdir"/etc/group "$root_tmpdir"/lib/group /tmp/group.$$
mv /tmp/group.$$ "$root_tmpdir"/etc/group

sed \
    -e 's/passwd:.*$/& altfiles/' \
    -e 's/group.*$/& altfiles/' \
    -i "$root_tmpdir"/etc/nsswitch.conf

mv "$root_tmpdir"/var/lib/rpm "$root_tmpdir"/lib/rpm
sed 's/\%{_var}\/lib\/rpm/\/lib\/rpm/' -i "$root_tmpdir"/usr/lib/rpm/macros

kernel=$(find "$root_tmpdir"/boot -type f -name "vmlinuz-*")
sha=$(sha256sum "$kernel" | awk '{print $1;}')
mv "$kernel" "$kernel-$sha"

rm -f \
    "$root_tmpdir"/boot/vmlinuz \
    "$root_tmpdir"/boot/initrd*

cat <<EOF > "$root_tmpdir"/ostree.conf
d /run/ostree 0755 root root -
f /run/ostree/initramfs-mount-var 0755 root root -
EOF

chroot "$root_tmpdir" dracut \
    -v \
    --reproducible \
    --gzip \
    --no-hostonly \
    -f /boot/initramfs-"$sha" \
    --add ignition \
    --add ostree \
    --include /ostree.conf /etc/tmpfiles.d/ostree.conf \
    --include /etc/systemd/network/eth0.network /etc/systemd/network/eth0.network \
    --omit-drivers=floppy \
    --omit=nfs \
    --omit=lvm \
    --omit=iscsi \
    --kver "$(ls "$root_tmpdir"/lib/modules)"

rm -rf "$root_tmpdir"/usr/etc
mv "$root_tmpdir"/etc "$root_tmpdir"/usr/etc

# shellcheck disable=SC2155
version="$(python3 "$__dir"/../stream.py \
    "$stream" \
    "$repo_root" \
    version \
    --next major \
    --view full)"

version_path="$(python3 "$__dir"/../stream.py \
    "$stream" \
    "$repo_root" \
    version \
    --next major \
    --view path)"

mkdir -p "$VARS_DIR"/"$version_path"
rsync -av "$root_tmpdir"/var "$VARS_DIR"/"$version_path"

rm -rf "${root_tmpdir:?}"/var
mkdir "$root_tmpdir"/var

# shellcheck disable=SC2153
commit=$(
    ostree commit \
        --repo="$ostree_dir" \
        --tree=dir="$root_tmpdir" \
        -b "$STREAM" \
        -m "$message" \
        --no-xattrs \
        --no-bindings \
        --mode-ro-executables \
        --add-metadata-string=version="$version")

cd "$VARS_DIR" || exit 1
ln -sf "$version_path" "$commit"

rm -rf "$tmpdir"

echo "$commit"