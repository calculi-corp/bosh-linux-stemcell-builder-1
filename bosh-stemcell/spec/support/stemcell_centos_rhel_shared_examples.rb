shared_examples_for 'a CentOS or RHEL stemcell' do

  context 'Linux kernel modules' do
    context '/lib/modules' do
      describe command('ls -1 /lib/modules | wc -l') do
        before do
          skip 'inapplicable to RHEL 8: the RHEL 8.5 kernel RPM installs 2 kernel dirs at "/lib/modules/<KERNEL_VERSION>"' if ENV['OS_NAME'] == 'rhel' && ENV['OS_VERSION'] == '8'
        end

        it('should match only 1 kernel dir') { expect(subject.stdout).to eq "1\n" }
      end
    end
  end

  context 'installed by dev_tools_config' do
    describe file('/var/vcap/bosh/etc/dev_tools_file_list') do
      it('has GCC installed') { expect(subject.content).to match '/usr/bin/gcc' }
    end
  end

  context 'installed by image_install_grub' do
    describe file('/etc/fstab') do
      it { should be_file }
      its(:content) { should include 'UUID=' }
      its(:content) { should include '/ ext4 defaults 1 1' }
    end

    describe 'mounted file systems: /etc/fstab should mount nfs with nodev, nosuid (stig: V-38652) (stig: V-38654)' do
      describe file('/etc/fstab') do
        it { should be_file }
        it('has no nfs mounts') { expect(subject.content).to_not include 'nfs' }
      end
    end

    # GRUB 2 configuration
    describe file('/boot/grub2/grub.cfg') do
      its(:content) { should match 'net.ifnames=0' }
      its(:content) { should match 'selinux=0' }
      its(:content) { should match 'plymouth.enable=0' }
      its(:content) { should_not match 'xen_blkfront.sda_is_xvda=1' }
      it('single-user mode boot should be disabled (stig: V-38586)') do
        expect(subject.content).to_not match 'single'
      end

      it('should set the user name and password for grub menu (stig: V-38585)') do
        expect(subject.content).to match 'set superusers=vcap'
      end
      it('should set the user name and password for grub menu (stig: V-38585)') do
        expect(subject.content).to match /^password_pbkdf2 vcap grub.pbkdf2.sha512.*/
      end

      it('should be of mode 600 (stig: V-38583)') { should be_mode(0600) }
      it('should be owned by root (stig: V-38579)') { should be_owned_by('root') }
      it('should be grouped into root (stig: V-38581)') do
        expect(subject.group).to eq('root')
      end
    end

    # GRUB 0.97 configuration (used only on Amazon PV hosts) must have same kernel params as GRUB 2
    describe file('/boot/grub/grub.cfg') do
      its(:content) { should match 'net.ifnames=0' }
      its(:content) { should match 'selinux=0' }
      its(:content) { should match 'plymouth.enable=0' }
      its(:content) { should_not match 'xen_blkfront.sda_is_xvda=1' }

      it('should be of mode 600 (stig: V-38583)') { should be_mode(0600) }
      it('should be owned by root (stig: V-38579)') { should be_owned_by('root') }
      it('should be grouped into root (stig: V-38581)') do
        expect(subject.group).to eq('root')
      end
      it('audits processes that start prior to auditd (CIS-8.1.3)') do
        expect(subject.content).to match ' audit=1'
      end
    end
  end

  context 'modified by base_file_permissions' do
    describe 'disallow unsafe setuid binaries' do
      subject { command('find / -xdev -perm /ug=s -type f').stdout.split }

      it { should match_array(%w(/usr/bin/su /usr/bin/sudo)) }
    end

    describe 'disallow root login' do
      describe file('/etc/ssh/sshd_config') do
        its(:content) { should match /^PermitRootLogin no$/ }
      end
    end
  end

  context 'installed by system-network on all IaaSes', { exclude_on_warden: true } do
    describe file('/etc/hostname') do
      it { should be_file }
      its (:content) { should eq('bosh-stemcell') }
    end
  end

  context 'installed by the system_network stage', {
    exclude_on_warden: true,
    exclude_on_azure: true,
  } do
    describe file('/etc/sysconfig/network') do
      it { should be_file }
      its(:content) { should match 'NETWORKING=yes' }
      its(:content) { should match 'NETWORKING_IPV6=no' }
      its(:content) { should match 'HOSTNAME=bosh-stemcell' }
      its(:content) { should match 'NOZEROCONF=yes' }
    end

    describe file('/etc/NetworkManager/NetworkManager.conf') do
      it { should be_file }
      its(:content) { should match 'plugins=ifcfg-rh' }
      its(:content) { should match 'no-auto-default=*' }
    end
  end

  context 'installed by the system_azure_network stage', {
    exclude_on_aws: true,
    exclude_on_google: true,
    exclude_on_vcloud: true,
    exclude_on_vsphere: true,
    exclude_on_warden: true,
    exclude_on_openstack: true,
  } do
    describe file('/etc/sysconfig/network') do
      it { should be_file }
      its(:content) { should match 'NETWORKING=yes' }
      its(:content) { should match 'NETWORKING_IPV6=no' }
      its(:content) { should match 'HOSTNAME=bosh-stemcell' }
      its(:content) { should match 'NOZEROCONF=yes' }
    end

    describe file('/etc/sysconfig/network-scripts/ifcfg-eth0') do
      it { should be_file }
      its(:content) { should match 'DEVICE=eth0' }
      its(:content) { should match 'BOOTPROTO=dhcp' }
      its(:content) { should match 'ONBOOT=on' }
      its(:content) { should match 'TYPE="Ethernet"' }
    end
  end

  context 'installed by bosh_aws_agent_settings', {
    exclude_on_google: true,
    exclude_on_openstack: true,
    exclude_on_vcloud: true,
    exclude_on_vsphere: true,
    exclude_on_warden: true,
    exclude_on_azure: true,
  } do
    describe file('/var/vcap/bosh/agent.json') do
      it { should be_valid_json_file }
      its(:content) { should match '"Type": "HTTP"' }
      its(:content) { should include('"PartitionerType": "parted"') }
    end
  end

  context 'installed by bosh_google_agent_settings', {
    exclude_on_aws: true,
    exclude_on_openstack: true,
    exclude_on_vcloud: true,
    exclude_on_vsphere: true,
    exclude_on_warden: true,
    exclude_on_azure: true,
  } do
    describe file('/var/vcap/bosh/agent.json') do
      it { should be_valid_json_file }
      its(:content) { should match '"Type": "InstanceMetadata"' }
      its(:content) { should include('"PartitionerType": "parted"') }
    end
  end

  context 'installed by bosh_vsphere_agent_settings', {
    exclude_on_aws: true,
    exclude_on_google: true,
    exclude_on_vcloud: true,
    exclude_on_openstack: true,
    exclude_on_warden: true,
    exclude_on_azure: true,
   } do
    describe file('/var/vcap/bosh/agent.json') do
      it { should be_valid_json_file }
      its(:content) { should match '"Type": "CDROM"' }
      its(:content) { should include('"PartitionerType": "parted"') }
    end
  end

  context 'installed by bosh_azure_agent_settings', {
    exclude_on_aws: true,
    exclude_on_google: true,
    exclude_on_vcloud: true,
    exclude_on_vsphere: true,
    exclude_on_warden: true,
    exclude_on_openstack: true,
  } do
    describe file('/var/vcap/bosh/agent.json') do
      it { should be_valid_json_file }
      its(:content) { should match '"Type": "File"' }
      its(:content) { should match '"MetaDataPath": ""' }
      its(:content) { should match '"UserDataPath": "/var/lib/waagent/CustomData"' }
      its(:content) { should match '"SettingsPath": "/var/lib/waagent/CustomData"' }
      its(:content) { should match '"UseServerName": true' }
      its(:content) { should match '"UseRegistry": true' }
      its(:content) { should include('"PartitionerType": "parted"') }
    end
  end
end
