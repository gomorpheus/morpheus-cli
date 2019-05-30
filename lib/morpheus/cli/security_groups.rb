# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::SecurityGroups
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  register_subcommands :list, :get, :add, :update, :remove, :use, :unuse
  register_subcommands :'add-location', :'remove-location'
  set_default_subcommand :list
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @security_groups_interface = @api_client.security_groups
    @security_group_rules_interface = @api_client.security_group_rules
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
    @active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
  end

  def handle(args)
    handle_subcommand(args)
  end


  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.list(params)
        return
      end
      json_response = @security_groups_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'securityGroups')
      return 0 if render_result

      title = "Morpheus Security Groups"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      security_groups = json_response['securityGroups']
      
      if security_groups.empty?
        print yellow,"No security groups found.",reset,"\n"
      else
        active_id = @active_security_group[@appliance_name.to_sym]
        # table_color = options[:color] || cyan
        # rows = security_groups.collect do |security_group|
        #   {
        #     id: security_group['id'].to_s + ((security_group['id'] == active_id.to_i) ? " (active)" : ""),
        #     name: security_group['name'],
        #     description: security_group['description']
        #   }
        # end

        # columns = [
        #   :id,
        #   :name,
        #   :description,
        #   # :ports,
        #   # :status,
        # ]
        columns = {
          "ID" => 'id',
          "NAME" => 'name',
          #"DESCRIPTION" => 'description',
          "DESCRIPTION" => lambda {|it| truncate_string(it['description'], 30) },
          #"USED BY" => lambda {|it| it['associations'] ? it['associations'] : '' },
          "SCOPED CLOUD" => lambda {|it| it['zone'] ? it['zone']['name'] : 'All' },
          "SOURCE" => lambda {|it| it['syncSource'] == 'external' ? 'SYNCED' : 'CREATED' }
        }
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(security_groups, columns, options)
        print reset
        if json_response['meta']
          print_results_pagination(json_response)
        else
          print_results_pagination({'meta'=>{'total'=>(json_response['securityGroupCount'] ? json_response['securityGroupCount'] : security_groups.size),'size'=>security_groups.size,'max'=>(params['max']||25),'offset'=>(params['offset']||0)}})
        end
        # print reset
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      @security_groups_interface.setopts(options)

      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @security_groups_interface.dry.get(args[0].to_i)
        else
          print_dry_run @security_groups_interface.dry.list({name:args[0]})
        end
        return 0
      end
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?
      json_response = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        json_response = {'securityGroup' => security_group}  # skip redundant request
      else
        json_response = @security_groups_interface.get(security_group['id'])
      end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_group = json_response['securityGroup']
      print_h1 "Morpheus Security Group"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Scoped Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : 'All' },
        "Source" => lambda {|it| it['syncSource'] == 'external' ? 'SYNCED' : 'CREATED' }
      }
      print_description_list(description_cols, security_group)
      print reset,"\n"

      if security_group['locations'] && security_group['locations'].size > 0
        print_h2 "Locations"
        print cyan
        location_cols = {
          "ID" => 'id',
          "CLOUD" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
          "EXTERNAL ID" => lambda {|it| it['externalId'] },
          "RESOURCE POOL" => lambda {|it| it['zonePool'] ? it['zonePool']['name'] : '' }
        }
        puts as_pretty_table(security_group['locations'], location_cols)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on( '--name Name', String, "Name of the security group" ) do |val|
        options[:options]['description'] = val
      end
      opts.on( '--description Description', String, "Description of the security group" ) do |val|
        options[:options]['description'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    if args[0]
      options[:options]['name'] = args[0]
    end
    connect(options)
    begin

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'securityGroup' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'securityGroup' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'securityGroup' => passed_options})  unless passed_options.empty?

        # Name
        options[:options]['name'] = options[:name] if options.key?(:name)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options[:options])
        payload['securityGroup']['name'] = v_prompt['name']

        # Description
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false}], options[:options])
        payload['securityGroup']['description'] = v_prompt['description']

      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.create(payload)
        return 0
      end
      json_response = @security_groups_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group #{json_response['securityGroup']['name']}"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      opts.on( '--name Name', String, "Name of the security group" ) do |val|
        options[:options]['description'] = val
      end
      opts.on( '--description Description', String, "Description of the security group" ) do |val|
        options[:options]['description'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload['securityGroup'].deep_merge!(passed_options)  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'securityGroup' => {
          }
        }
        # allow arbitrary -O options
        payload['securityGroup'].deep_merge!(passed_options)  unless passed_options.empty?
        
        if passed_options.empty?
          raise_command_error "Specify atleast one option to update.\n#{optparse}"
        end

      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.update(security_group['id'], payload)
        return 0
      end
      json_response = @security_groups_interface.update(security_group['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Updated security group #{json_response['securityGroup']['name']}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the security group: #{security_group['name']}?")
        return 9, "aborted command"
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.delete(security_group['id'])
        return
      end
      json_response = @security_groups_interface.delete(security_group['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      #list([])
      print_green_success "Removed security group #{args[0]}"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_location(args)
    cloud_id = nil
    resource_pool_id = nil
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.on( '--resource-pool ID', String, "ID of the resource pool (VPC)" ) do |val|
        resource_pool_id = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'securityGroupLocation' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'securityGroupLocation' => {
          }
        }
        payload.deep_merge!({'securityGroupLocation' => passed_options})  unless passed_options.empty?
        # load cloud
        if cloud_id.nil?
          puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
          return 1
        end
        cloud = find_cloud_by_name_or_id(cloud_id)
        return 1 if cloud.nil?

        payload['securityGroupLocation']['zoneId'] = cloud['id']

        if cloud['securityServer']
          if cloud['securityServer']['type'] == 'amazon'
            if resource_pool_id
              payload['securityGroupLocation']['customOptions'] = {'vpc' => resource_pool_id}
            elsif cloud['config'] && cloud['config']['vpc']
              payload['securityGroupLocation']['customOptions'] = {'vpc' => cloud['config']['vpc']}
            end
          elsif cloud['securityServer']['type'] == 'azure'
            if resource_pool_id
              payload['securityGroupLocation']['customOptions'] = {'resourceGroup' => resource_pool_id}
            elsif cloud['config'] && cloud['config']['resourceGroup']
              payload['securityGroupLocation']['customOptions'] = {'resourceGroup' => cloud['config']['resourceGroup']}
            end
          end
        end
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.create_location(security_group['id'], payload)
        return 0
      end
      json_response = @security_groups_interface.create_location(security_group['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group location #{security_group['name']} - #{cloud['name']}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_location(args)
    cloud_id = nil
    resource_pool_id = nil
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      security_group_location = nil
      if security_group['locations']
        security_group_location = security_group['locations'].find {|it| it['zone']['id'] == cloud['id'] }
      end
      if security_group_location.nil?
        print_red_alert "Security group location not found for cloud #{cloud['name']}"
        return 1
      end

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the security group location #{security_group['name']} - #{cloud['name']}?")
        return 9, "aborted command"
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.delete_location(security_group['id'], security_group_location['id'])
        return 0
      end
      json_response = @security_groups_interface.delete_location(security_group['id'], security_group_location['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group location #{security_group['name']} - #{cloud['name']}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def add_rule(args)
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [options]")
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'rule' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'rule' => {
          }
        }
        payload.deep_merge!({'rule' => passed_options})  unless passed_options.empty?

        # prompt
        
      end

      @security_group_rules_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_group_rules_interface.dry.create(security_group['id'], payload)
        return 0
      end
      json_response = @security_group_rules_interface.create(security_group['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group rule #{json_response['id']}"
      #get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_rule(args)
    params = {}
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[security-group] [id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?
      
      security_group_rule = find_security_group_rule_by_id(security_group['id'], args[1])
      return 1 if security_group_rule.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the security group rule: #{security_group_rule['id']}?")
        return 9, "aborted command"
      end

      @security_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @security_groups_interface.dry.delete_location(security_group['id'], security_group_location['id'])
        return 0
      end
      json_response = @security_groups_interface.delete_location(security_group['id'], security_group_location['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Created security group location #{security_group['name']} - #{cloud['name']}"
      get([security_group['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # JD: still need this??
  def use(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
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

      security_group = find_security_group_by_name_or_id(args[0])
      return 1 if security_group.nil?

      if !security_group.nil?
        @active_security_group[@appliance_name.to_sym] = security_group['id']
        ::Morpheus::Cli::SecurityGroups.save_security_group(@active_security_group)
        puts cyan, "Using Security Group #{args[0]}", reset
      else
        puts red, "Security Group not found", reset
      end
      return 0
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
    File.join(Morpheus::Cli.home_directory,"securitygroup")
  end

  def self.save_security_group(new_config)
    fn = security_group_file_path
    if !Dir.exists?(File.dirname(fn))
      FileUtils.mkdir_p(File.dirname(fn))
    end
    File.open(fn, 'w') {|f| f.write new_config.to_yaml } #Store
    FileUtils.chmod(0600, fn)
    new_config
  end

  private

   def find_security_group_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_security_group_by_id(val)
    else
      return find_security_group_by_name(val)
    end
  end

  def find_security_group_by_id(id)
    begin
      json_response = @security_groups_interface.get(id.to_i)
      return json_response['securityGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Security Group not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_security_group_by_name(name)
    json_response = @security_groups_interface.list({name: name.to_s})
    security_groups = json_response['securityGroups']
    if security_groups.empty?
      print_red_alert "Security Group not found by name #{name}"
      return nil
    elsif security_groups.size > 1
      print_red_alert "#{security_groups.size} security groups found by name #{name}"
      rows = security_groups.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return security_groups[0]
    end
  end

  def find_security_group_rule_by_id(security_group_id, id)
    begin
      json_response = @security_groups_interface.get(security_group_id.to_i, id.to_i)
      return json_response['rule']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Security Group Rule not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

end
