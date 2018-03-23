require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::KeyPairs
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  register_subcommands :list, :get, :add, :update, :remove
  alias_subcommand :details, :get

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @key_pairs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).key_pairs
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:account, :list, :json])
    end
    optparse.parse!(args)
    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      json_response = @key_pairs_interface.list(account_id, params)
      key_pairs = json_response['keyPairs']
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        title = "Morpheus Key Pairs"
        subtitles = []
        if account
          subtitles << "Account: #{account['name']}".strip
        end
        if params[:phrase]
          subtitles << "Search: #{params[:phrase]}".strip
        end
        print_h1 title, subtitles
        if key_pairs.empty?
          puts yellow,"No key pairs found.",reset
        else
          print_key_pairs_table(key_pairs)
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
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:account, :json])
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      key_pair = find_key_pair_by_name_or_id(account_id, args[0])
      exit 1 if key_pair.nil?

      if options[:json]
        print JSON.pretty_generate({keyPair: key_pair})
        print "\n"
      else
        print_h1 "Key Pair Details"
        print cyan
        if account
          # print_description_list({"Account" => lambda {|it| it['account'] ? it['account']['name'] : '' } }, key_pair)
          print_description_list({"Account" => lambda {|it| account['name'] } }, key_pair)
        end
        print_description_list({
          "ID" => 'id',
          "Name" => 'name',
          "Fingerprint" => 'fingerprint',
          "MD5" => 'md5',
          # "Has Private Key" => lambda {|it| format_boolean(it['hasPrivateKey']) },
          # "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) }
          #"Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
        }, key_pair)

        print_h2 "Public Key"
        print cyan
        puts "#{key_pair['publicKey']}"
        
        if key_pair['hasPrivateKey']
          # print_h2 "Private Key"
          # print cyan
          # puts "(hidden)"
        else
          # print_h2 "Private Key"
          print cyan, "\n"
          puts "This is only a public key.  It does not include a private key."
        end

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
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('', '--public-key-file FILENAME', "Public Key File" ) do |filename|
        if File.exists?(File.expand_path(filename))
          options['publicKey'] = File.read(File.expand_path(filename))
          options[:options] ||= {}
          options[:options]['publicKey'] = options['publicKey']
        else
          print_red_alert "File not found: #{filename}"
          exit 1
        end
      end

      opts.on('', '--public-key TEXT', "Public Key Text" ) do |val|
        options['publicKey'] = val
        options[:options] ||= {}
        options[:options]['publicKey'] = options['publicKey']
      end

      opts.on('', '--private-key-file FILENAME', "Private Key File" ) do |filename|
        if File.exists?(File.expand_path(filename))
          options['privateKey'] = File.read(File.expand_path(filename))
          options[:options] ||= {}
          options[:options]['privateKey'] = options['privateKey']
        else
          print_red_alert "File not found: #{filename}"
          exit 1
        end
      end

      opts.on('', '--private-key TEXT', "Private Key Text" ) do |val|
        options['privateKey'] = val
        options[:options] ||= {}
        options[:options]['privateKey'] = options['privateKey']
      end

      build_common_options(opts, options, [:account, :options, :json, :dry_run])
    end
    optparse.parse!(args)
    # if args.count < 1
    #   puts optparse
    #   exit 1
    # end
    if args[0]
      options[:options] ||= {}
      options[:options]['name'] ||= args[0]
    end
    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      params = Morpheus::Cli::OptionTypes.prompt(add_key_pair_option_types, options[:options], @api_client, options[:params])

      if params['publicKey'].to_s.empty? && params['privateKey'].to_s.empty?
        print_red_alert "publicKey or privateKey is required"
        return 1
      end
      # if !params['publicKey']
      #   print_red_alert "publicKey is required"
      #   exit 1
      # elsif !params['privateKey']
      #   print_red_alert "privateKey is required"
      #   exit 1
      # end
      #params['name'] = args[0]

      key_pair_payload = params.select {|k,v| ['name','publicKey', 'privateKey', 'passphrase'].include?(k) }
      payload = {keyPair: key_pair_payload}
      if options[:dry_run]
        print_dry_run @key_pairs_interface.dry.create(account_id, payload)
        return
      end
      json_response = @key_pairs_interface.create(account_id, payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Key Pair #{key_pair_payload['name']} added"
        get([json_response['keyPair']['id']])
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
      build_option_type_options(opts, options, update_key_pair_option_types)
      build_common_options(opts, options, [:account, :options, :json, :dry_run])
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      key_pair = find_key_pair_by_name_or_id(account_id, args[0])
      exit 1 if key_pair.nil?

      #params = Morpheus::Cli::OptionTypes.prompt(update_key_pair_option_types, options[:options], @api_client, options[:params])
      params = options[:options] || {}

      if params.empty?
        puts optparse
        option_lines = update_key_pair_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      key_pair_payload = params.select {|k,v| ['name'].include?(k) }
      payload = {keyPair: key_pair_payload}
      if options[:dry_run]
        print_dry_run @key_pairs_interface.dry.update(account_id, key_pair['id'], payload)
        return
      end
      json_response = @key_pairs_interface.update(account_id, key_pair['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Key Pair #{key_pair_payload['name'] || key_pair['name']} updated"
        get([json_response['keyPair']['id']])
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
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run])
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
      # current user account by default
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      # allow finding by ID since name is not unique!
      key_pair = find_key_pair_by_name_or_id(account_id, args[0])
      exit 1 if key_pair.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the key pair #{key_pair['name']}?")
        exit
      end
      if options[:dry_run]
        print_dry_run @key_pairs_interface.dry.destroy(account_id, key_pair['id'])
        return
      end
      json_response = @key_pairs_interface.destroy(account_id, key_pair['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Key Pair #{key_pair['name']} removed"
        # list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private
  def find_key_pair_by_name_or_id(account_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_key_pair_by_id(account_id, val)
    else
      return find_key_pair_by_name(account_id, val)
    end
  end

  def find_key_pair_by_id(account_id, id)
    raise "#{self.class} has not defined @key_pairs_interface" if @key_pairs_interface.nil?
    begin
      json_response = @key_pairs_interface.get(account_id, id.to_i)
      return json_response['keyPair']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Key Pair not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_key_pair_by_name(account_id, name)
    raise "#{self.class} has not defined @key_pairs_interface" if @key_pairs_interface.nil?
    key_pairs = @key_pairs_interface.list(account_id, {name: name.to_s})['keyPairs']
    if key_pairs.empty?
      print_red_alert "Key Pair not found by name #{name}"
      return nil
    elsif key_pairs.size > 1
      print_red_alert "#{key_pairs.size} key_pairs by name #{name}"
      print_key_pairs_table(key_pairs, {color: red})
      print reset,"\n"
      return nil
    else
      return key_pairs[0]
    end
  end

  def print_key_pairs_table(key_pairs, opts={})
    table_color = opts[:color] || cyan
    rows = key_pairs.collect do |key_pair|
      {
        id: key_pair['id'],
        name: key_pair['name'],
        fingerprint: key_pair['fingerprint'],
        md5: key_pair['md5'],
        dateCreated: format_local_dt(key_pair['dateCreated'])
      }
    end
    print table_color
    tp rows, [
      :id,
      :name,
      {:fingerprint => {:width => 47} },
      # {:md5 => {:width => 32} },
      {:dateCreated => {:display_name => "Date Created"} }
    ]
    print reset
  end


  def add_key_pair_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'publicKey', 'fieldLabel' => 'Public Key', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'privateKey', 'fieldLabel' => 'Private Key', 'type' => 'text', 'required' => false, 'displayOrder' => 3},
      {'fieldName' => 'passphrase', 'fieldLabel' => 'Passphrase', 'type' => 'password', 'required' => false, 'displayOrder' => 4},
    ]
  end

  def update_key_pair_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
    ]
  end

end
