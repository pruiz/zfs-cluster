%{!?srcrev:	%define srcrev master}

Name:           zfs-agents
Version:        1.0.%{srcrev}
Release:        1%{?dist}
Summary:        RedHat Cluster Suite's ZFS Resource Agents & Tools
Group:          System Environment/Base
License:        GPL
URL:            http://www.github.com/pruiz/zfs-cluster
Source:		zfs-agents-%{srcrev}.tar.gz
BuildRoot:      %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
Requires:       resource-agents
BuildArch:      noarch

%description
RedHat Cluster Suite's ZFS Resource Agents & Tools

%prep

%build

%install
rm -rf %{buildroot}
install -d "%{buildroot}%{_datadir}/cluster"
install -m 755 "%{SOURCE0}" "%{buildroot}%{_datadir}/cluster/"
install -d "%{buildroot}%{_datadir}/cluster/utils"
install -m 755 "%{SOURCE1}" "%{buildroot}%{_datadir}/cluster/utils"
install -d "%{buildroot}%{_datadir}/cluster/zfs.d"

%clean
rm -rf %{buildroot}

%package -n zfs-agents

%files -n zfs-agents
%defattr(-,root,root,-)
%dir %{_datadir}/cluster/zfs.d
%attr(755,root,root) %{_datadir}/cluster/zfs.sh
%attr(755,root,root) %{_datadir}/cluster/utils/zfs-share.sh

%changelog

