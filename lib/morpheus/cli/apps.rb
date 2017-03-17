# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/provisioning_helper'

class Morpheus::Cli::Apps
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  register_subcommands :list, :get, :add, :update, :remove, :add_instance, :remove_instance, :logs, :firewall_disable, :firewall_enable, :security_groups, :apply_security_groups
  alias_subcommand :details, :get
  set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @apps_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).apps
    @instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
    @instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      if options[:dry_run]
        print_dry_run @apps_interface.dry.get(params)
        return
      end

      json_response = @apps_interface.get(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      apps = json_response['apps']
      title = "Morpheus Apps"
      subtitles = []
      # if group
      #   subtitles << "Group: #{group['name']}".strip
      # end
      # if cloud
      #   subtitles << "Cloud: #{cloud['name']}".strip
      # end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if apps.empty?
        print cyan,"No apps found.",reset,"\n"
      else
        print_apps_table(apps)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      
      build_option_type_options(opts, options, add_app_option_types(false))
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    connect(options)
    begin
      options[:options] ||= {}
      # use the -g GROUP or active group by default
      options[:options]['group'] ||= options[:group] || @active_group_id
      # support [name] as first argument still
      if args[0]
        options[:options]['name'] = args[0]
      end

      payload = {
        'app' => {}
      }
      params = Morpheus::Cli::OptionTypes.prompt(add_app_option_types, options[:options], @api_client, options[:params])
      group = find_group_by_name_or_id_for_provisioning(params.delete('group'))
      payload['app'].merge!(params)
      payload['app']['group'] = {id: group['id']}

      # todo: allow adding instances with creation..

      if options[:dry_run]
        print_dry_run @apps_interface.dry.create(payload)
        return
      end
      json_response = @apps_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Added app #{payload['app']['name']}"
        list([])
        # details_options = [payload['app']['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.get(app['id'])
        return
      end
      json_response = @apps_interface.get(app['id'])
      app = json_response['app']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      print_h1 "App Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        # "Group" => lambda {|it| it['group'] ? it['group']['name'] : it['siteId'] },
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Status" => lambda {|it| format_app_status(it) }
      }
      print_description_list(description_cols, app)

      stats = app['stats']
      if app['instanceCount'].to_i > 0
        print_h2 "App Usage"
        print_stats_usage(stats, {include: [:memory, :storage]})
      end

      app_tiers = app['appTiers']
      if app_tiers.empty?
        puts yellow, "This app is empty", reset
      else
        app_tiers.each do |app_tier|
          print_h2 "Tier: #{app_tier['tier']['name']}\n"
          print cyan
          instances = (app_tier['appInstances'] || []).collect {|it| it['instance']}
          if instances.empty?
            puts yellow, "This tier is empty", reset
          else
            instance_table = instances.collect do |instance|
              # JD: fix bug here, status is not returned because withStats: false !?
              status_string = instance['status'].to_s
              if status_string == 'running'
                status_string = "#{green}#{status_string.upcase}#{cyan}"
              elsif status_string == 'stopped' or status_string == 'failed'
                status_string = "#{red}#{status_string.upcase}#{cyan}"
              elsif status_string == 'unknown'
                status_string = "#{white}#{status_string.upcase}#{cyan}"
              else
                status_string = "#{yellow}#{status_string.upcase}#{cyan}"
              end
              connection_string = ''
              if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
                connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
              end
              {id: instance['id'], name: instance['name'], connection: connection_string, environment: instance['instanceContext'], nodes: instance['containers'].count, status: status_string, type: instance['instanceType']['name'], group: !instance['group'].nil? ? instance['group']['name'] : nil, cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil}
            end
            tp instance_table, :id, :name, :cloud, :type, :environment, :nodes, :connection, :status
          end
        end
      end
      print cyan

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, update_app_option_types(false))
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])

      payload = {
        'app' => {id: app["id"]}
      }

      params = options[:options] || {}

      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        exit 1
      end

      #puts "parsed params is : #{params.inspect}"
      app_keys = ['name', 'description']
      params = params.select {|k,v| app_keys.include?(k) }
      payload['app'].merge!(params)

      if options[:dry_run]
        print_dry_run @apps_interface.dry.update(app["id"], payload)
        return
      end

      json_response = @apps_interface.update(app["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated app #{app['name']}"
        list([])
        # details_options = [payload['app']['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def add_instance(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [instance] [tier]")
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    # optional [tier] and [instance] arguments
    if args[1] && args[1] !~ /\A\-/
      options[:instance_name] = args[1]
      if args[2] && args[2] !~ /\A\-/
        options[:tier_name] = args[2]
      end
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])

      # Only supports adding an existing instance right now..

      payload = {}

      if options[:instance_name]
        instance = find_instance_by_name_or_id(options[:instance_name])
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
        instance = find_instance_by_name_or_id(v_prompt['instance'])
      end
      payload[:instanceId] = instance['id']

      if options[:tier_name]
        payload[:tierName] = options[:tier_name]
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tier', 'fieldLabel' => 'Tier', 'type' => 'text', 'required' => true, 'description' => 'Enter the name of the tier'}], options[:options])
        payload[:tierName] = v_prompt['tier']
      end

      if options[:dry_run]
        print_dry_run @apps_interface.dry.add_instance(app['id'], payload)
        return
      end
      json_response = @apps_interface.add_instance(app['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added instance #{instance['name']} to app #{app['name']}"
        list([])
        # details_options = [app['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :auto_confirm])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the app '#{app['name']}'?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @apps_interface.dry.destroy(app['id'])
        return
      end
      json_response = @apps_interface.destroy(app['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed app #{app['name']}"
        list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_instance(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [instance]")
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    # optional [tier] and [instance] arguments
    if args[1] && args[1] !~ /\A\-/
      options[:instance_name] = args[1]
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])

      payload = {}

      if options[:instance_name]
        instance = find_instance_by_name_or_id(options[:instance_name])
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
        instance = find_instance_by_name_or_id(v_prompt['instance'])
      end
      payload[:instanceId] = instance['id']

      if options[:dry_run]
        print_dry_run @apps_interface.dry.remove_instance(app['id'], payload)
        return
      end

      json_response = @apps_interface.remove_instance(app['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed instance #{instance['name']} from app #{app['name']}"
        list([])
        # details_options = [app['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:list, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      containers = []
      app['appTiers'].each do |app_tier|
        app_tier['appInstances'].each do |app_instance|
          containers += app_instance['instance']['containers']
        end
      end
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @logs_interface.dry.container_logs(containers, params)
        return
      end
      logs = @logs_interface.container_logs(containers, params)
      if options[:json]
        print JSON.pretty_generate(logs)
        print "\n"
      else
        logs['data'].reverse.each do |log_entry|
          log_level = ''
          case log_entry['level']
          when 'INFO'
            log_level = "#{blue}#{bold}INFO#{reset}"
          when 'DEBUG'
            log_level = "#{white}#{bold}DEBUG#{reset}"
          when 'WARN'
            log_level = "#{yellow}#{bold}WARN#{reset}"
          when 'ERROR'
            log_level = "#{red}#{bold}ERROR#{reset}"
          when 'FATAL'
            log_level = "#{red}#{bold}FATAL#{reset}"
          end
          puts "[#{log_entry['ts']}] #{log_level} - #{log_entry['message']}"
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

=begin
  def stop(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.stop(app['id'])
        return
      end
      @apps_interface.stop(app['id'])
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.start(app['id'])
        return
      end
      @apps_interface.start(app['id'])
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.restart(app['id'])
        return
      end
      @apps_interface.restart(app['id'])
      list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
=end

  def firewall_disable(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.firewall_disable(app['id'])
        return
      end
      @apps_interface.firewall_disable(app['id'])
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.firewall_enable(app['id'])
        return
      end
      @apps_interface.firewall_enable(app['id'])
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.security_groups(app['id'])
        return
      end
      json_response = @apps_interface.security_groups(app['id'])
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for App: #{app['name']}"
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      if securityGroups.empty?
        print yellow,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [--clear] [-s]")
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        options[:securityGroupIds] = []
        clear_or_secgroups_specified = true
      end
      opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        options[:securityGroupIds] = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      opts.on( '-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    if !clear_or_secgroups_specified
      puts optparse
      exit 1
    end

    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @apps_interface.dry.apply_security_groups(app['id'], options)
        return
      end
      @apps_interface.apply_security_groups(app['id'], options)
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def add_app_option_types(connected=true)
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this app'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => (connected ? get_available_groups() : []), 'required' => true},
    ]
  end

  def update_app_option_types(connected=true)
    list = add_app_option_types(connected)
    list = list.reject {|it| ["group"].include? it['fieldName'] }
    list.each {|it| it['required'] = false }
    list
  end

  def find_app_by_id(id)
    app_results = @apps_interface.get(id.to_i)
    if app_results['app'].empty?
      print_red_alert "App not found by id #{id}"
      exit 1
    end
    return app_results['app']
  end

  def find_app_by_name(name)
    app_results = @apps_interface.get({name: name})
    if app_results['apps'].empty?
      print_red_alert "App not found by name #{name}"
      exit 1
    end
    return app_results['apps'][0]
  end

  def find_app_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_app_by_id(val)
    else
      return find_app_by_name(val)
    end
  end

  def print_apps_table(apps, opts={})
    output = ""
    table_color = opts[:color] || cyan
    rows = apps.collect do |app|
      instances_str = (app['instanceCount'].to_i == 1) ? "1 Instance" : "#{app['instanceCount']} Instances"
      containers_str = (app['containerCount'].to_i == 1) ? "1 Container" : "#{app['containerCount']} Containers"
      {
        id: app['id'],
        name: app['name'],
        instances: instances_str,
        containers: containers_str,
        account: app['account'] ? app['account']['name'] : nil,
        status: format_app_status(app, table_color),
        #dateCreated: format_local_dt(app['dateCreated'])
      }
    end
    print table_color
    tp rows, [
      :id,
      :name,
      :instances,
      :containers,
      #:account,
      :status,
      #{:dateCreated => {:display_name => "Date Created"} }
    ]
    print reset
  end

  def format_app_status(app, return_color=cyan)
    out = ""
    status_string = app['status']
    if app['instanceCount'].to_i == 0
      # show this instead of WARNING
      out <<  "#{white}EMPTY#{return_color}"
    elsif status_string == 'running'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out <<  "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'unknown'
      out <<  "#{white}#{status_string.upcase}#{return_color}"
    else
      out <<  "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end
end
