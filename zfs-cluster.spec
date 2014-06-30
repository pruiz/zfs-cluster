%{!?srcrev:	%define srcrev master}

Name:           zfs-cluster
Version:        1.0.%{srcrev}
Release:        1%{?dist}
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

install -d "%{buildroot}%{_datadir}/cluster"
install -d "%{buildroot}%{_datadir}/cluster/utils"
install -d "%{buildroot}%{_datadir}/cluster/zfs.d"
install -d "%{buildroot}%{_datadir}/cluster/extra"
install -m 755 zfs-agents/zfs.sh "%{buildroot}%{_datadir}/cluster/"
install -m 755 zfs-agents/zfs-share.sh "%{buildroot}%{_datadir}/cluster/utils"

install -m 755 iscsi-target-agents/utils/iscsi-lib.sh "%{buildroot}%{_datadir}/cluster/utils"
install -m 755 iscsi-target-agents/utils/iscsi-helper.sh "%{buildroot}%{_datadir}/cluster/utils"
install -m 755 iscsi-target-agents/iscsi-lun.sh "%{buildroot}%{_datadir}/cluster/"
install -m 755 iscsi-target-agents/iscsi-luns.sh "%{buildroot}%{_datadir}/cluster/"
install -m 755 iscsi-target-agents/iscsi-target.sh "%{buildroot}%{_datadir}/cluster/"
install -m 755 proxmox/zfs-lun-helper.sh "%{buildroot}%{_datadir}/cluster/extra/proxmox-zfs-helper.sh"

%clean
rm -rf %{buildroot}

%package -n zfs-agents
Summary:        RedHat Cluster Suite's ZFS Resource Agents & Tools

%description -n zfs-agents
RedHat Cluster Suite's ZFS Resource Agents & Tools

%files -n zfs-agents
%defattr(-,root,root,-)
%dir %{_datadir}/cluster/zfs.d
%attr(755,root,root) %{_datadir}/cluster/zfs.sh
%attr(755,root,root) %{_datadir}/cluster/utils/zfs-share.sh

%package -n iscsi-target-agents
Summary:	RedHat Cluster Suite's (dynamic) iSCSI Resource Agentes & Tools

%description -n iscsi-target-agents
RedHat Cluster Suite's (enhanced) iSCSI Resource Agentes & Tools

%files -n iscsi-target-agents
%defattr(-,root,root,-)
%attr(755,root,root) %{_datadir}/cluster/utils/iscsi-lib.sh
%attr(755,root,root) %{_datadir}/cluster/utils/iscsi-helper.sh
%attr(755,root,root) %{_datadir}/cluster/iscsi-lun.sh
%attr(755,root,root) %{_datadir}/cluster/iscsi-luns.sh
%attr(755,root,root) %{_datadir}/cluster/iscsi-target.sh
%attr(755,root,root) %{_datadir}/cluster/extra/proxmox-zfs-helper.sh

%changelog

