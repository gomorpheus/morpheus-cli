# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityGroups
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :remove, :use, :unuse

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @security_groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).security_groups
    @active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
  end

  def handle(args)
    handle_subcommand(args)
  end


  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.list(params)
        return
      end
      json_response = @security_groups_interface.list(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_groups = json_response['securityGroups']
      print "\n" ,cyan, bold, "Morpheus Security Groups\n","==================", reset, "\n\n"
      if security_groups.empty?
        puts yellow,"No Security Groups currently configured.",reset
      else
        active_id = @active_security_group[@appliance_name.to_sym]
        security_groups.each do |security_group|
          if @active_security_group[@appliance_name.to_sym] == security_group['id']
            print cyan, "=> #{security_group['id']}: #{security_group['name']} (#{security_group['description']})\n"
          else
            print cyan, "   #{security_group['id']}: #{security_group['name']} (#{security_group['description']})\n"
          end
        end
        if active_id
          print cyan, "\n\n# => - current", reset
        end
      end
      print reset,"\n"
          rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.get({id: args[0]})
        return
      end
      json_response = @security_groups_interface.get({id: args[0]})
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_group = json_response['securityGroup']
      print "\n" ,cyan, bold, "Morpheus Security Group\n","==================", reset, "\n\n"
      if security_group.nil?
        puts yellow,"Security Group not found by id #{args[0]}",reset
      else
        print cyan, "=  #{security_group['id']}: #{security_group['name']} (#{security_group['description']})\n"
      end
      print reset,"\n\n"
          rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    params = {:securityGroup => {}}
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on( '-d', '--description Description', "Description of the security group" ) do |description|
        params[:securityGroup][:description] = description
      end
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    params[:securityGroup][:name] = args[0]
    connect(options)
    begin
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.create(params)
        return
      end
      json_response = @security_groups_interface.create(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      json_response = @security_groups_interface.get({id: args[0]})
      security_group = json_response['securityGroup']
      if security_group.nil?
        puts "Security Group not found by id #{args[0]}"
        return
      end
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.delete(security_group['id'])
        return
      end
      json_response = @security_groups_interface.delete(security_group['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def use(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id] [--none]")
      opts.on('--none','--none', "Do not use an active group.") do |json|
        options[:unuse] = true
      end
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    if args.length < 1 && !options[:unuse]
      puts optparse
      return
    end
    connect(options)
    begin

      if options[:unuse]
        if @active_security_group[@appliance_name.to_sym] 
          @active_security_group.delete(@appliance_name.to_sym)
        end
        ::Morpheus::Cli::SecurityGroups.save_security_group(@active_security_group)
        unless options[:quiet]
          print cyan
          puts "Switched to no active security group."
          print reset
        end
        print reset
        return # exit 0
      end

      json_response = @security_groups_interface.get({id: args[0]})
      security_group = json_response['securityGroup']
      if !security_group.nil?
        @active_security_group[@appliance_name.to_sym] = security_group['id']
        ::Morpheus::Cli::SecurityGroups.save_security_group(@active_security_group)
        puts cyan, "Using Security Group #{args[0]}", reset
      else
        puts red, "Security Group not found", reset
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def unuse(args)
    use(args + ['--none'])
  end

  def self.load_security_group_file
    remote_file = security_group_file_path
    if File.exist? remote_file
      return YAML.load_file(remote_file)
    else
      {}
    end
  end

  def self.security_group_file_path
    home_dir = Dir.home
    morpheus_dir = File.join(home_dir,".morpheus")
    if !Dir.exist?(morpheus_dir)
      Dir.mkdir(morpheus_dir)
    end
    return File.join(morpheus_dir,"securitygroup")
  end

  def self.save_security_group(security_group_map)
    File.open(security_group_file_path, 'w') {|f| f.write security_group_map.to_yaml } #Store
  end

end
