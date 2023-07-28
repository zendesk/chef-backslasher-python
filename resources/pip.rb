unified_mode true

property :python_path, String, default: 'python'
property :package_name, String, name_property: true # Name of the package
property :package_url, String # URL of package location. Optional, used to specify git locations etc
property :version, [String, nil], default: nil # Package to install. Defaults to "latest"
property :virtualenv, String # Venv
property :timeout, Integer, default: 900
property :user, String, regex: Chef::Config[:user_valid_regex]
property :group, String, regex: Chef::Config[:group_valid_regex]
property :environment, Hash
property :install_options, Array, default: [] # Additional options for installation
property :smart_install, [true, false], default: false

actions :install, :remove, :upgrade
default_action :install

load_current_value do |new_resource|
  under_package_name = new_resource.package_name.gsub('_', '-')
  pattern = Regexp.new("^#{Regexp.escape(under_package_name)} \\(([^)]+)\\)$", true)
  my_line = pip_command('list', new_resource).stdout.lines.map{|line| pattern.match(line)}.compact.first
  if my_line
    version my_line[1]
  end
end

def real_python_path(new_resource)
  if new_resource.virtualenv
    "#{new_resource.virtualenv}/bin/python"
  else
    new_resource.python_path
  end
end

def should_install(requirement_row, install_options, new_resource)
  return true unless new_resource.smart_install # Skip if not smart install
  # Run script from current cookbook
  cookbook_path = ::File.dirname(::File.dirname(__FILE__))
  file_path = ::File.join(cookbook_path,'files/default/smart_install.py')

  pro = Mixlib::ShellOut.new([real_python_path(new_resource), file_path, *install_options, requirement_row]).run_command
  return pro.stdout.strip == 'True'
end

def pip_command(subcommand, new_resource)
  options = { :timeout => new_resource.timeout, :user => new_resource.user, :group => new_resource.group }
  environment = Hash.new
  environment['HOME'] = Dir.home(new_resource.user) if new_resource.user
  environment.merge!(new_resource.environment) if new_resource.environment && !new_resource.environment.empty?
  options[:environment] = environment
  # Append pip starter to subcommand
  subcommand=subcommand.clone()
  if subcommand.class==Array
    subcommand.unshift(real_python_path(new_resource),'-m','pip.__main__')
  elsif subcommand.class==String
    subcommand="#{real_python_path(new_resource)} -m pip.__main__ #{subcommand}"
  else
    raise 'Invalid subcommand type. Supply Array or String'
  end

  Mixlib::ShellOut.new(subcommand, options).run_command
end

def install_name(new_resource)
  install_name = if new_resource.package_url
           # We have a url to install from
           new_resource.package_url
         elsif new_resource.version.nil?
           # We have no specific version
           new_resource.package_name
         elsif version and version == new_resource.version
           # We have the current version
           nil
         else
           # We have a specific version
           "#{new_resource.package_name}==#{new_resource.version}"
         end
end

action :install do
  args = ['install', *new_resource.install_options, install_name(new_resource)]
  if install_name(new_resource) && should_install(install_name(new_resource), args, new_resource)
    converge_by "Installing backslasher_python_pip #{new_resource.package_name}" do
      pip_command(args, new_resource)
    end
  end
end

def should_remove?
  if current_resource.version.nil?
    # Nothing installed
    false
  elsif new_resource.version.nil?
    # Something is installed, remove it
    true
  elsif new_resource.version == current_resrouce.version
    # We're supposed to remove a version, and this is it
    true
  else
    # We're supposed to remove a version, and this is not it
    false
  end
end

action :remove do
  if should_remove? # ~FC023
    converge_by "Removing backslasher_python_pip #{new_resource.package_name}" do
      pip_command(['uninstall','--yes',new_resource.package_name], new_resource)
    end
  end
end

action :upgrade do
  # Upgrading
  new_resource.install_options << '--upgrade'
  self.run_action(:install)
end
