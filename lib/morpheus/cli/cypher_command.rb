require 'json'
require 'yaml'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::CypherCommand
  include Morpheus::Cli::CliCommand

  set_command_name :cypher

  register_subcommands :list, :get, :add, :remove, :decrypt
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @cypher_interface = @api_client.cypher
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List cypher items."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @cypher_interface.dry.list(params)
        return 0
      end
      json_response = @cypher_interface.list(params)      
      cypher_items = json_response["cyphers"]
      if options[:json]
        puts as_json(json_response, options, "cyphers")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "cyphers")
        return 0
      elsif options[:csv]
        puts records_as_csv(cypher_items, options)
        return 0
      end
      title = "Morpheus Cypher List"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if cypher_items.empty?
        print cyan,"No cypher items found.",reset,"\n"
      else
        cypher_columns = {
          "ID" => 'id',
          "KEY" => lambda {|it| it["itemKey"] || it["key"] },
          "LEASE REMAINING" => lambda {|it| it['expireDate'] ? format_local_dt(it['expireDate']) : "" },
          "DATED CREATED" => lambda {|it| format_local_dt(it["dateCreated"]) },
          "LAST ACCESSED" => lambda {|it| format_local_dt(it["lastAccessed"]) }
        }
        if options[:include_fields]
          cypher_columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(cypher_items, cypher_columns, options)
        print reset
        print_results_pagination(json_response)
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
    do_decrypt = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on(nil, '--decrypt', 'Display the decrypted value') do
        do_decrypt = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a cypher." + "\n" +
                    "[id] is required. This is the id or key of a cypher."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @cypher_interface.dry.get(args[0].to_i)
        else
          print_dry_run @cypher_interface.dry.list({name:args[0]})
        end
        return
      end
      cypher_item = find_cypher_by_name_or_id(args[0])
      return 1 if cypher_item.nil?
      json_response = {'cypher' => cypher_item}  # skip redundant request
      decrypt_json_response = nil
      if do_decrypt
        decrypt_json_response = @cypher_interface.decrypt(cypher_item["id"])
      end
      # json_response = @cypher_interface.get(cypher_item['id'])
      cypher_item = json_response['cypher']
      if options[:json]
        puts as_json(json_response, options, "cypher")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "cypher")
        return 0
      elsif options[:csv]
        puts records_as_csv([cypher_item], options)
        return 0
      end
      print_h1 "Cypher Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        # what here
        "Key" => lambda {|it| it["itemKey"] },
        #"Value" => lambda {|it| it["value"] || "************" },
        "Lease Remaining" => lambda {|it| format_local_dt(it["expireDate"]) },
        "Date Created" => lambda {|it| format_local_dt(it["dateCreated"]) },
        "Last Accessed" => lambda {|it| format_local_dt(it["lastAccessed"]) }
      }
      print_description_list(description_cols, cypher_item)
      if decrypt_json_response
        print_h2 "Decrypted Value"
        print cyan
        puts decrypt_json_response["cypher"] ? decrypt_json_response["cypher"]["itemValue"] : ""
      end
      print reset, "\n"

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def decrypt(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Decrypt the value of a cypher." + "\n" +
                    "[id] is required. This is the id or key of a cypher."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      cypher_item = find_cypher_by_name_or_id(args[0])
      return 1 if cypher_item.nil?
      if options[:dry_run]
        print_dry_run @cypher_interface.dry.decrypt(cypher_item["id"], params)
        return
      end
      
      cypher_item = find_cypher_by_name_or_id(args[0])
      return 1 if cypher_item.nil?

      json_response = @cypher_interface.decrypt(cypher_item["id"], params)
      if options[:json]
        puts as_json(json_response, options, "cypher")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "cypher")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response["crypt"]], options)
        return 0
      end
      print_h1 "Cypher Decrypt"
      print cyan
      print_description_list({
        "ID" => 'id',
        "Key" => lambda {|it| it["itemKey"] },
        "Value" => lambda {|it| it["itemValue"] }
        }, json_response["cypher"])
      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--key VALUE', String, "Key for this cypher") do |val|
        params['itemKey'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new cypher."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && options[:options].keys.size > 0
        
        # support [key] as first argument
        if args[0]
          params['itemKey'] = args[0]
        end
        # Key
        if !params['itemKey']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'itemKey', 'fieldLabel' => 'Key', 'type' => 'text', 'required' => true, 'description' => cypher_key_help}], options)
          params['itemKey'] = v_prompt['itemKey']
        end

        # Value
        value_is_required = false
        cypher_mount_type = params['itemKey'].split("/").first
        if cypher_mount_type == ["secret", "password"].include?(cypher_mount_type)
          value_is_required = true
        end

        if !params['itemValue']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'itemValue', 'fieldLabel' => 'Value', 'type' => 'text', 'required' => value_is_required, 'description' => "Value for this cypher"}], options)
          params['itemValue'] = v_prompt['itemValue']
        end

        # Lease
        if !params['leaseTimeout']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'leaseTimeout', 'fieldLabel' => 'Lease', 'type' => 'text', 'required' => false, 'description' => cypher_lease_help}], options)
          params['leaseTimeout'] = v_prompt['leaseTimeout']
        end
        if !params['leaseTimeout'].to_s.empty?
          params['leaseTimeout'] = params['leaseTimeout'].to_i
        end

        # construct payload
        payload = {
          'cypher' => params
        }
      end

      if options[:dry_run]
        print_dry_run @cypher_interface.dry.create(payload)
        return
      end
      json_response = @cypher_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Added cypher"
        # list([])
        cypher_item = json_response['cypher']
        get([cypher_item['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # def update(args)
  # end

  # def decrypt(args)
  # end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a cypher." + "\n" +
                    "[id] is required. This is the id or key of a cypher."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      cypher_item = find_cypher_by_name_or_id(args[0])
      return 1 if cypher_item.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cypher #{cypher_item['itemKey']}?")
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @cypher_interface.dry.destroy(cypher_item["id"])
        return
      end
      json_response = @cypher_interface.destroy(cypher_item["id"])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Deleted cypher #{cypher_item['itemKey']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

  def find_cypher_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_cypher_by_id(val)
    else
      return find_cypher_by_name(val)
    end
  end

  def find_cypher_by_id(id)
    begin
      
      json_response = @cypher_interface.get(id.to_i)
      return json_response['cypher']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Cypher not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_cypher_by_name(name)
    # api supports name as alias for itemKey
    json_response = @cypher_interface.list({name: name.to_s})
    
    cypher_items = json_response['cyphers']
    if cypher_items.empty?
      print_red_alert "Cypher not found by name #{name}"
      return nil
    elsif cypher_items.size > 1
      print_red_alert "#{cypher_items.size} cyphers found by name #{name}"
      rows = cypher_items.collect do |cypher_item|
        {id: cypher_item['id'], name: cypher_item['name']}
      end
      print red
      print as_pretty_table(rows, [:id, :name])
      print reset,"\n"
      return nil
    else
      return cypher_items[0]
    end
  end

  def cypher_key_help
    """
Keys can have different behaviors depending on the specified mountpoint.
Available Mountpoints:
password - Generates a secure password of specified character length in the key pattern (or 15) with symbols, numbers, upper case, and lower case letters (i.e. password/15/mypass generates a 15 character password).
tfvars - This is a module to store a tfvars file for terraform.
secret - This is the standard secret module that stores a key/value in encrypted form.
uuid - Returns a new UUID by key name when requested and stores the generated UUID by key name for a given lease timeout period.
key - Generates a Base 64 encoded AES Key of specified bit length in the key pattern (i.e. key/128/mykey generates a 128-bit key)"""
  end

  def cypher_lease_help
    """
Lease time in MS (defaults to 32 days)
Quick MS Time Reference:
Day: 86400000
Week: 604800000
Month (30 days): 2592000000
Year: 31536000000"""
  end

end

