# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Accounts
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  register_subcommands :list, :get, :add, :update, :remove
  alias_subcommand :details, :get

  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @users_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).users
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @roles_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).roles
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      json_response = @accounts_interface.list(params)
      accounts = json_response['accounts']
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print "\n" ,cyan, bold, "Morpheus Accounts\n","==================", reset, "\n\n"
        if accounts.empty?
          puts yellow,"No accounts found.",reset
        else
          print_accounts_table(accounts)
          print_results_pagination(json_response)
        end
        print reset,"\n"
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
      build_common_options(opts, options, [:json])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin

      account = find_account_by_name_or_id(args[0])
      exit 1 if account.nil?

      if options[:json]
        print JSON.pretty_generate({account: account})
        print "\n"
      else
        print "\n" ,cyan, bold, "Account Details\n","==================", reset, "\n\n"
        print cyan
        puts "ID: #{account['id']}"
        puts "Name: #{account['name']}"
        puts "Description: #{account['description']}"
        puts "Currency: #{account['currency']}"
        # puts "# Users: #{account['usersCount']}"
        # puts "# Instances: #{account['instancesCount']}"
        puts "Date Created: #{format_local_dt(account['dateCreated'])}"
        puts "Last Updated: #{format_local_dt(account['lastUpdated'])}"
        status_state = nil
        if account['active']
          status_state = "#{green}ACTIVE#{cyan}"
        else
          status_state = "#{red}INACTIVE#{cyan}"
        end
        puts "Status: #{status_state}"
        print "\n" ,cyan, bold, "Account Instance Limits\n","==================", reset, "\n\n"
        print cyan
        puts "Max Storage (bytes): #{account['instanceLimits'] ? account['instanceLimits']['maxStorage'] : 0}"
        puts "Max Memory (bytes): #{account['instanceLimits'] ? account['instanceLimits']['maxMemory'] : 0}"
        puts "CPU Count: #{account['instanceLimits'] ? account['instanceLimits']['maxCpu'] : 0}"
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[options]")
      build_common_options(opts, options, [:options, :json])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = Morpheus::Cli::OptionTypes.prompt(add_account_option_types, options[:options], @api_client, options[:params])
      #puts "parsed params is : #{params.inspect}"
      account_keys = ['name', 'description', 'currency']
      account_payload = params.select {|k,v| account_keys.include?(k) }
      account_payload['currency'] = account_payload['currency'].to_s.empty? ? "USD" : account_payload['currency'].upcase
      if !account_payload['instanceLimits']
        account_payload['instanceLimits'] = {}
        account_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
        account_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
        account_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
      end
      if params['role'].to_s != ''
        role = find_role_by_name(nil, params['role'])
        exit 1 if role.nil?
        account_payload['role'] = {id: role['id']}
      end
      request_payload = {account: account_payload}
      json_response = @accounts_interface.create(request_payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Account #{account_payload['name']} added"
        get([account_payload["name"]])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_common_options(opts, options, [:options, :json])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      account = find_account_by_name_or_id(args[0])
      exit 1 if account.nil?

      #params = Morpheus::Cli::OptionTypes.prompt(update_account_option_types, options[:options], @api_client, options[:params])
      params = options[:options] || {}

      if params.empty?
        puts optparse
        option_lines = update_account_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      #puts "parsed params is : #{params.inspect}"
      account_keys = ['name', 'description', 'currency', 'instanceLimits']
      account_payload = params.select {|k,v| account_keys.include?(k) }
      account_payload['currency'] = account_payload['currency'].upcase unless account_payload['currency'].to_s.empty?
      if !account_payload['instanceLimits']
        account_payload['instanceLimits'] = {}
        account_payload['instanceLimits']['maxStorage'] = params['instanceLimits.maxStorage'].to_i if params['instanceLimits.maxStorage'].to_s.strip != ''
        account_payload['instanceLimits']['maxMemory'] = params['instanceLimits.maxMemory'].to_i if params['instanceLimits.maxMemory'].to_s.strip != ''
        account_payload['instanceLimits']['maxCpu'] = params['instanceLimits.maxCpu'].to_i if params['instanceLimits.maxCpu'].to_s.strip != ''
      end
      if params['role'].to_s != ''
        role = find_role_by_name(nil, params['role'])
        exit 1 if role.nil?
        account_payload['role'] = {id: role['id']}
      end
      request_payload = {account: account_payload}
      json_response = @accounts_interface.update(account['id'], request_payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        account_name = account_payload['name'] || account['name']
        print_green_success "Account #{account_name} updated"
        get([account_name])
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
      build_common_options(opts, options, [:auto_confirm, :json])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      # allow finding by ID since name is not unique!
      account = find_account_by_name_or_id(args[0])
      exit 1 if account.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the account #{account['name']}?")
        exit
      end
      json_response = @accounts_interface.destroy(account['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Account #{account['name']} removed"
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def add_account_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2},
      {'fieldName' => 'role', 'fieldLabel' => 'Base Role', 'type' => 'text', 'displayOrder' => 3},
      {'fieldName' => 'currency', 'fieldLabel' => 'Currency', 'type' => 'text', 'displayOrder' => 4},
      {'fieldName' => 'instanceLimits.maxStorage', 'fieldLabel' => 'Max Storage (bytes)', 'type' => 'text', 'displayOrder' => 5},
      {'fieldName' => 'instanceLimits.maxMemory', 'fieldLabel' => 'Max Memory (bytes)', 'type' => 'text', 'displayOrder' => 6},
      {'fieldName' => 'instanceLimits.maxCpu', 'fieldLabel' => 'CPU Count', 'type' => 'text', 'displayOrder' => 7},
    ]
  end

  def update_account_option_types
    add_account_option_types
  end

end
