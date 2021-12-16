# Updating CentOS 8.2 Linux kernel to the last release

Edit `/etc/yum.repos.d/CentOS-Vault.repo` as below.

	# CentOS Vault contains rpms from older releases in the CentOS-8
	# tree.
	[C8.2-base]
	name=CentOS-8.2-Base
	baseurl=http://vault.centos.org/8.2.2004/BaseOS/$basearch/os/
	gpgcheck=1
	gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
	enabled=1

	[C8.2-AppStream]
	name=CentOS-8.2-Updates
	baseurl=http://vault.centos.org/8.2.2004/AppStream/$basearch/os/
	gpgcheck=1
	gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
	enabled=1

	[C8.2-extras]
	name=CentOS-8.2-Extras
	baseurl=http://vault.centos.org/8.2.2004/extras/$basearch/os/
	gpgcheck=1
	gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
	enabled=1

Issue `yum --disablerepo=* --enablerepo=C8.2-base,C8.2-AppStream,C8.2-extras update kernel`
