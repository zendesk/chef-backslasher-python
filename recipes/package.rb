#
# Cookbook:: backslasher-python
# Recipe:: default
#
# GPLv2
#
#

major_version = node['platform_version'].to_i

# COOK-1016 Handle RHEL/CentOS namings of python packages, by installing EPEL
# repo & package
if platform_family?('rhel') && major_version < 6
  include_recipe 'yum-epel'
  python_pkgs = %w(python26 python26-devel)
  node.default['python']['binary'] = '/usr/bin/python26'
elsif platform?("ubuntu") && node['platform_version'].to_f >= 22.04
  python_pkgs = %w(python3 python3-venv)
else
  python_pkgs = value_for_platform_family(
                  'debian'  => %w(python python-dev),
                  'rhel'    => %w(python python-devel),
                  'fedora'  => %w(python python-devel),
                  'freebsd' => ['python'],
                  'smartos' => ['python27'],
                  'default' => %w(python python-dev)
                )
end

python_pkgs.each do |pkg|
  package pkg do
    action :install
  end
end
