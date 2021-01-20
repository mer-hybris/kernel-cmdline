Name:       kernel-cmdline
Summary:    Modify kernel cmdline
Version:    1.1.0
Release:    1
Group:      System/Libraries
License:    ASL 2.0
URL:        https://github.com/mer-hybris/kernel-cmdline
Source0:    %{name}-%{version}.tar.bz2
Source1:    kernel-cmdline.sh

%description
Modify kernel command line with ease.

%prep
%setup -q -n %{name}-%{version}/mkbootimg

%build
make %{?jobs:-j%jobs}

%install
rm -rf %{buildroot}
install -D -m 755 mkbootimg %{buildroot}%{_libexecdir}/%{name}/mkbootimg
install -D -m 755 unpackbootimg %{buildroot}%{_libexecdir}/%{name}/unpackbootimg
install -D -m 755 %{SOURCE1} %{buildroot}%{_bindir}/kernel-cmdline

%files
%defattr(-,root,root,-)
%dir %{_libexecdir}/kernel-cmdline
%{_libexecdir}/%{name}/mkbootimg
%{_libexecdir}/%{name}/unpackbootimg
%{_bindir}/kernel-cmdline
