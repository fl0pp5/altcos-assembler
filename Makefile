install-deps:
	sudo apt-repo add 330305
	sudo apt-get update
	sudo apt-get install -y \
		hasher \
		hasher-priv \
		mkimage \
		fakeroot \
		basesystem \
		rpm-build \
		sisyphus_check \
		mkisofs \
		time \
		apt-utils \
		openssl \
		podman \
		dracut \
		ignition \
		butane \
		skopeo \
		python3-module-pydantic \
		python3-module-pyaml \
		python3-module-rpm \
		python3-module-altcos-common \
		libvirt \
		libvirt-kvm \
		libvirt-qemu \
		parted

get-mkimage:
	mkdir -p ALTCOS; cd ALTCOS; \
		git clone https://github.com/fl0pp5/mkimage-profiles.git

fetch-submodules:
	git submodule update --init --recursive

setup-hasher:
	sudo systemctl enable --now hasher-privd.service
	sudo hasher-useradd $(USER)
	sudo sh -c "echo allowed_mountpoints=/proc >> /etc/hasher-priv/system"

setup-libvirt:
	sudo gpasswd -a $(USER) vmusers
	sudo systemctl enable --now libvirtd

all: install-deps get-mkimage fetch-submodules setup-hasher setup-libvirt
