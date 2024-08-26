Name:       kernel-cmdline
Summary:    Modify kernel cmdline
Version:    1.1.3
Release:    1
License:    ASL 2.0
URL:        https://github.com/mer-hybris/kernel-cmdline
Source0:    %{name}-%{version}.tar.bz2
Source1:    kernel-cmdline.sh
Requires:   android-tools-mkbootimg

%description
Modify kernel command line with ease.

%prep
%autosetup -n %{name}-%{version}

%install
install -D -m 755 %{SOURCE1} %{buildroot}%{_bindir}/kernel-cmdline

%files
%license LICENSE
%{_bindir}/kernel-cmdline
