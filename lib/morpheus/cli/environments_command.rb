require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::EnvironmentsCommand
  include Morpheus::Cli::CliCommand
  set_command_name :environments
  register_subcommands :list, :get, :add, :update, :remove, :'toggle-active'

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @environments_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).environments
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @environments_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @environments_interface.dry.list(params)
        return 0
      end
      json_response = @environments_interface.list(params)
      render_result = render_with_format(json_response, options, 'environments')
      return 0 if render_result
      environments = json_response['environments']
      unless options[:quiet]
        title = "Morpheus Environments"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if environments.empty?
          print yellow,"No Environments found.",reset
        else
          print_environments_table(environments)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      @environments_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @environments_interface.dry.get(args[0])
        else
          print_dry_run @environments_interface.dry.list({name: args[0].to_s})
        end
        return 0
      end
      environment = find_environment_by_name_or_id(args[0])
      return 1 if environment.nil?
      json_response = {'environment' => environment}
      render_result = render_with_format(json_response, options, 'environment')
      return 0 if render_result
      
      unless options[:quiet]
        print_h1 "Environment Details"
        print cyan

        print_description_list({
          "ID" => 'id',
          "Name" => 'name',
          "Code" => 'code',
          "Description" => 'description',
          "Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
          "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
          "Sort Order" => lambda {|it| it['sortOrder'] },
          "Active" => lambda {|it| format_boolean(it['active']) },
          #"Created" => lambda {|it| format_local_dt(it['dateCreated']) }
        }, environment)
        print reset,"\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_environment_option_types)
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      options[:options] ||= {}
      options[:options]['name'] ||= args[0]
    end
    connect(options)
    begin
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'environment' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'environment' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'environment' => passed_options}) unless passed_options.empty?
        # prompt for options
        params = Morpheus::Cli::OptionTypes.prompt(add_environment_option_types, options[:options], @api_client, options[:params])
        payload.deep_merge!({'environment' => params}) unless params.empty?
      end

      @environments_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @environments_interface.dry.create(payload)
        return
      end
      json_response = @environments_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['environment']  ? json_response['environment']['name'] : ''
        print_green_success "Environment #{display_name} added"
        get([json_response['environment']['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_environment_option_types)
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin

      environment = find_environment_by_name_or_id(args[0])
      return 1 if environment.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'environment' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'environment' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'environment' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_environment_option_types, options[:options], @api_client, options[:params])
        params = passed_options

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

        payload.deep_merge!({'environment' => params}) unless params.empty?
      end
      @environments_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @environments_interface.dry.update(environment['id'], payload)
        return
      end
      json_response = @environments_interface.update(environment['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['environment'] ? json_response['environment']['name'] : ''
        print_green_success "Environment #{display_name} updated"
        get([json_response['environment']['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      environment = find_environment_by_name_or_id(args[0])
      return 1 if environment.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the environment #{environment['name']}?")
        return 9, "aborted command"
      end
      @environments_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @environments_interface.dry.destroy(environment['id'])
        return
      end
      json_response = @environments_interface.destroy(environment['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Environment #{environment['name']} removed"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def toggle_active(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [on|off]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 1 || args.count > 2
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[1]
      params['active'] = (args[1].to_s == 'on' || args[1].to_s == 'true')
    end
    connect(options)
    begin

      environment = find_environment_by_name_or_id(args[0])
      return 1 if environment.nil?

      @environments_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @environments_interface.dry.toggle_active(environment['id'], params)
        return
      end
      json_response = @environments_interface.toggle_active(environment['id'], params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['environment'] ? json_response['environment']['name'] : ''
        print_green_success "Environment #{display_name} updated"
        get([json_response['environment']['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private
  def find_environment_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_environment_by_id(val)
    else
      return find_environment_by_name(val)
    end
  end

  def find_environment_by_id(id)
    raise "#{self.class} has not defined @environments_interface" if @environments_interface.nil?
    begin
      json_response = @environments_interface.get(id)
      return json_response['environment']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Environment not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_environment_by_name(name)
    raise "#{self.class} has not defined @environments_interface" if @environments_interface.nil?
    environments = @environments_interface.list({name: name.to_s})['environments']
    if environments.empty?
      print_red_alert "Environment not found by name #{name}"
      return nil
    elsif environments.size > 1
      print_red_alert "#{environments.size} environments by name #{name}"
      print_environments_table(environments, {color: red})
      print reset,"\n"
      return nil
    else
      return environments[0]
    end
  end

  def print_environments_table(environments, opts={})
    table_color = opts[:color] || cyan
    rows = environments.collect do |environment|
      {
        id: environment['id'],
        name: environment['name'],
        code: environment['code'],
        description: environment['description'],
        active: format_boolean(environment['active'])
      }
    end
    columns = [
      :id,
      :name,
      :code,
      :description,
      :active
    ]
    print as_pretty_table(rows, columns, opts)
    print reset
  end


  def add_environment_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'displayOrder' => 3},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'displayOrder' => 6},
      {'fieldName' => 'sortOrder', 'fieldLabel' => 'Sort Order', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 5}
    ]
  end

  def update_environment_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
      #{'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'displayOrder' => 3},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => 'private', 'displayOrder' => 6},
      {'fieldName' => 'sortOrder', 'fieldLabel' => 'Sort Order', 'type' => 'number', 'required' => false, 'defaultValue' => 0, 'displayOrder' => 5}
    ]
  end

end
