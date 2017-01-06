%{!?srcver:	%define srcver 1.0}
%{!?srcrev:	%define srcrev master}
%{!?buildno:	%define buildno 1}

%define _provider netway

Name:           zfs-cluster
Version:        %{srcver}
Release:        %{buildno}.%{srcrev}%{?dist}
Summary:        RedHat Cluster Suite's ZFS Resource Agents & Tools
Group:          System Environment/Base
License:        GPL
URL:            http://www.github.com/pruiz/zfs-cluster
Source:		%{name}-%{srcrev}.tar.gz
BuildRoot:      %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
Requires:       resource-agents
BuildArch:      noarch

%description
RedHat Cluster Suite's ZFS Resource Agents & Tools

%prep
mkdir -p "%{name}-%{srcrev}"
tar -zxvf %{SOURCE0} --strip-components=1 -C "%{name}-%{srcrev}"

%build

%install
rm -rf %{buildroot}
cd "%{name}-%{srcrev}"

install -d "%{buildroot}%{_libdir}/ocf/lib/%{_provider}"
install -d "%{buildroot}%{_libdir}/ocf/resource.d/%{_provider}"
install -d "%{buildroot}%{_datadir}/cluster/zfs.d"

install -m 755 zfs-agents/zfs.sh "%{buildroot}%{_libdir}/ocf/resource.d/%{_provider}"
install -m 755 zfs-agents/zfs-share.sh "%{buildroot}%{_libdir}/ocf/lib/%{_provider}"

install -m 755 iscsi-target-agents/utils/iscsi-lib.sh "%{buildroot}%{_libdir}/ocf/lib/%{_provider}"
install -m 755 iscsi-target-agents/utils/iscsi-helper.sh "%{buildroot}%{_libdir}/ocf/lib/%{_provider}"
install -m 755 iscsi-target-agents/iscsi-lun.sh "%{buildroot}%{_libdir}/ocf/resource.d/%{_provider}"
install -m 755 iscsi-target-agents/iscsi-luns.sh "%{buildroot}%{_libdir}/ocf/resource.d/%{_provider}"
install -m 755 iscsi-target-agents/iscsi-target.sh "%{buildroot}%{_libdir}/ocf/resource.d/%{_provider}"
install -m 755 proxmox/zfs-lun-helper.sh "%{buildroot}%{_libdir}/ocf/lib/%{_provider}/proxmox-zfs-helper.sh"

%clean
rm -rf %{buildroot}

%package -n zfs-agents
Summary:        RedHat Cluster Suite's ZFS Resource Agents & Tools

%description -n zfs-agents
RedHat Cluster Suite's ZFS Resource Agents & Tools

%files -n zfs-agents
%defattr(-,root,root,-)
%dir %{_datadir}/cluster/zfs.d
%attr(755,root,root) %{_libdir}/ocf/lib/%{_provider}/zfs-share.sh
%attr(755,root,root) %{_libdir}/ocf/resource.d/%{_provider}/zfs.sh

%package -n iscsi-target-agents
Summary:	RedHat Cluster Suite's (dynamic) iSCSI Resource Agentes & Tools

%description -n iscsi-target-agents
RedHat Cluster Suite's (enhanced) iSCSI Resource Agentes & Tools

%files -n iscsi-target-agents
%defattr(-,root,root,-)
%attr(755,root,root) %{_libdir}/ocf/lib/%{_provider}/iscsi-lib.sh
%attr(755,root,root) %{_libdir}/ocf/lib/%{_provider}/iscsi-helper.sh
%attr(755,root,root) %{_libdir}/ocf/lib/%{_provider}/proxmox-zfs-helper.sh
%attr(755,root,root) %{_libdir}/ocf/resource.d/%{_provider}/iscsi-lun.sh
%attr(755,root,root) %{_libdir}/ocf/resource.d/%{_provider}/iscsi-luns.sh
%attr(755,root,root) %{_libdir}/ocf/resource.d/%{_provider}/iscsi-target.sh

%changelog

