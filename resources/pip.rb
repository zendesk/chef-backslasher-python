property :python_path, String, default: 'python'
property :package_name, String, name_property: true
property :package_url, String
property :version, [String, nil], default: nil 
property :virtualenv, String
property :timeout, Integer, default: 900
property :user, String, regex: Chef::Config[:user_valid_regex]
property :group, String, regex: Chef::Config[:group_valid_regex]
property :environment, Hash
property :install_options, Array, default: [] 
property :smart_install, [true, false], default: false

action :install do
  pkg_name = install_name(new_resource)
  Chef::Log.warn("pkg_name: #{pkg_name}")
  args = ['install', *new_resource.install_options, pkg_name]
  if pkg_name && should_install(pkg_name, args, new_resource)
    converge_by "Installing backslasher_python_pip #{new_resource.package_name}" do
      pip_command(args, new_resource)
    end
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
  new_resource.install_options << '--upgrade'
  run_action(:install)
end

action_class do
  def current_version
    under_package_name = new_resource.package_name.gsub('_', '-')
    pattern = Regexp.new("^#{Regexp.escape(under_package_name)}\\s*([0-9.]+)\\s*$", true)
    pip_command('list', new_resource).stdout.lines.map{|line| pattern.match(line)}.compact&.first
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

    pro = Mixlib::ShellOut.new([real_python_path(new_resource), file_path, *install_options, requirement_row])
    pro.run_command
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
    Chef::Log.warn("Running: #{subcommand}")
    cmd = Mixlib::ShellOut.new(subcommand, options)
    cmd.run_command
    cmd
  end

  def install_name(new_resource)
    install_name = if new_resource.package_url
             # We have a url to install from
             new_resource.package_url
           elsif new_resource.version.nil?
             # We have no specific version
             new_resource.package_name
           elsif current_version and current_version == new_resource.version
             # We have the current version
             nil
           else
             # We have a specific version
             "#{new_resource.package_name}==#{new_resource.version}"
           end
  end

  def should_remove?
    if current_resource.version.nil?
      false
    elsif new_resource.version.nil?
      true
    elsif new_resource.version == current_resource.version
      true
    else
      false
    end
  end
end
