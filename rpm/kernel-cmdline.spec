Name:       kernel-cmdline
Summary:    Modify kernel cmdline
Version:    1.1.3
Release:    1
License:    ASL 2.0
URL:        https://github.com/mer-hybris/kernel-cmdline
Source0:    %{name}-%{version}.tar.bz2
Source1:    kernel-cmdline.sh
Patch1:     0001-mkbootimg-Fix-variable-scope.patch
Patch2:     0002-Turn-off-Werror-on-libmincrypt.patch

%description
Modify kernel command line with ease.

%prep
%autosetup -p1 -n %{name}-%{version}/mkbootimg

%build
%make_build

%install
install -D -m 755 mkbootimg %{buildroot}%{_libexecdir}/%{name}/mkbootimg
install -D -m 755 unpackbootimg %{buildroot}%{_libexecdir}/%{name}/unpackbootimg
install -D -m 755 %{SOURCE1} %{buildroot}%{_bindir}/kernel-cmdline

%files
%license NOTICE
%dir %{_libexecdir}/kernel-cmdline
%{_libexecdir}/%{name}/mkbootimg
%{_libexecdir}/%{name}/unpackbootimg
%{_bindir}/kernel-cmdline
