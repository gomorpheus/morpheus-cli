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
  
  def initialize() 
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
    if @access_token.empty?
      print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
      exit 1
    end
    @api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @key_pairs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).key_pairs
  end

  def handle(args)
    usage = "Usage: morpheus key-pairs [list,add,update,remove] [name]"
    if args.empty?
      puts "\n#{usage}\n\n"
      exit 1
    end

    case args[0]
      when 'list'
        list(args[1..-1])
      when 'details'
        details(args[1..-1])
      when 'add'
        add(args[1..-1])
      when 'update'
        update(args[1..-1])
      when 'remove'
        remove(args[1..-1])
      else
        puts "\n#{usage}\n\n"
        exit 127
    end
  end

  def list(args)
    usage = "Usage: morpheus key-pairs list [options]"
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:account, :list, :json])
    end
    optparse.parse(args)
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
        print "\n" ,cyan, bold, "Morpheus Key Pairs\n","==================", reset, "\n\n"
        if key_pairs.empty?
          puts yellow,"No key pairs found.",reset
        else
          print_key_pairs_table(key_pairs)
        end
        print reset,"\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def details(args)
    usage = "Usage: morpheus key-pairs details [name] [options]"
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:account, :json])
    end
    optparse.parse(args)

    if args.count < 1
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]

    connect(options)
    begin
    
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      # todo: key_pairs_response = @key_pairs_interface.list(account_id, {name: name})
      #       there may be response data outside of account that needs to be displayed

      # allow finding by ID since name is not unique!
      key_pair = ((name.to_s =~ /\A\d{1,}\Z/) ? find_key_pair_by_id(account_id, name) : find_key_pair_by_name(account_id, name) )
      exit 1 if key_pair.nil?

      if options[:json]
        print JSON.pretty_generate({keyPair: key_pair})
        print "\n"
      else
        print "\n" ,cyan, bold, "Key Pair Details\n","==================", reset, "\n\n"
        print cyan
        puts "ID: #{key_pair['id']}"
        puts "Name: #{key_pair['name']}"
        puts "MD5: #{key_pair['md5']}"
        puts "Date Created: #{format_local_dt(key_pair['dateCreated'])}"
        #puts "Last Updated: #{format_local_dt(key_pair['lastUpdated'])}"
        print reset,"\n\n"

        # todo: show public key

      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = "Usage: morpheus key-pairs add [name] [options]"

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

      build_common_options(opts, options, [:account, :options, :json])
    end
    
    if args.count < 1
      puts "\n#{optparse}\n\n"
      exit 1
    end
    optparse.parse(args)

    connect(options)
    
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      params = Morpheus::Cli::OptionTypes.prompt(add_key_pair_option_types, options[:options], @api_client, options[:params])

      if !params['publicKey']
        print_red_alert "publicKey is required"
        exit 1
      elsif !params['privateKey']
        print_red_alert "privateKey is required"
        exit 1
      end
      params['name'] = args[0]

      key_pair_payload = params.select {|k,v| ['name','publicKey', 'privateKey'].include?(k) }

      request_payload = {keyPair: key_pair_payload}
      json_response = @key_pairs_interface.create(account_id, request_payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Key Pair #{key_pair_payload['name']} added"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    usage = "Usage: morpheus key-pairs update [name] [options]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:account, :options, :json])
    end
    optparse.parse(args)

    if args.count < 1
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]

    connect(options)
    
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      key_pair = ((name.to_s =~ /\A\d{1,}\Z/) ? find_key_pair_by_id(account_id, name) : find_key_pair_by_name(account_id, name) )
      exit 1 if key_pair.nil?

      #params = Morpheus::Cli::OptionTypes.prompt(update_key_pair_option_types, options[:options], @api_client, options[:params])
      params = options[:options] || {}

      if params.empty?
        puts "\n#{usage}\n\n"
        option_lines = update_key_pair_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      key_pair_payload = params.select {|k,v| ['name'].include?(k) }
      request_payload = {keyPair: key_pair_payload}
      json_response = @key_pairs_interface.update(account_id, key_pair['id'], request_payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Key Pair #{key_pair_payload['name'] || key_pair['name']} updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    usage = "Usage: morpheus key-pairs remove [name]"
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:account, :auto_confirm, :json])
    end
    optparse.parse(args)

    if args.count < 1
      puts "\n#{usage}\n\n"
      exit 1
    end
    name = args[0]

    connect(options)
    begin
      # current user account by default
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      # allow finding by ID since name is not unique!
      key_pair = ((name.to_s =~ /\A\d{1,}\Z/) ? find_key_pair_by_id(account_id, name) : find_key_pair_by_name(account_id, name) )
      exit 1 if key_pair.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the key pair #{key_pair['name']}?")
        exit
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
      print reset,"\n\n"
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
        md5: key_pair['md5'],
        dateCreated: format_local_dt(key_pair['dateCreated']) 
      }
    end
    
    print table_color
    tp rows, [
      :id, 
      :name, 
      :md5,
      {:dateCreated => {:display_name => "Date Created"} }
    ]
    print reset
  end


  def add_key_pair_option_types
    [
      {'fieldName' => 'publicKey', 'fieldLabel' => 'Public Key', 'type' => 'text', 'required' => true, 'displayOrder' => 2},
      {'fieldName' => 'privateKey', 'fieldLabel' => 'Private Key', 'type' => 'text', 'required' => true, 'displayOrder' => 3},
    ]
  end

  def update_key_pair_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
    ]
  end

end
