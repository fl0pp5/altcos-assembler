Name: altcos-archives
Version: 0.1
Release: alt1

Summary: Archives to install ALTCOS
License: GPL-3.0-or-later
Group: System/Base

%description
Archives to install ALT Container OS

%install
mkdir -p %buildroot%_datadir/altcos/
install -m444 ../SOURCES/altcos_root.tar.xz %buildroot%_datadir/altcos/
install -m444 ../SOURCES/var.tar.xz %buildroot%_datadir/altcos/

%files
%_datadir/altcos/altcos_root.tar.xz
%_datadir/altcos/var.tar.xz
