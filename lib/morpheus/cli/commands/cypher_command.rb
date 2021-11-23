require 'morpheus/cli/cli_command'

class Morpheus::Cli::CypherCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'cypher'

  register_subcommands :list, :get, :put, :remove
  # some appropriate aliases
  #register_subcommands :read => :get, 
  #register_subcommands :write => :put
  #register_subcommands :add => :put
  #register_subcommands :delete => :remove
  # register_subcommands :destroy => :destroy
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    # @cypher_interface = @api_client.cypher
    @cypher_interface = @api_client.cypher
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      # opts.on('--details', '--details', "Show more details." ) do
      #   options[:details] = true
      # end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List cypher keys." + "\n" +
                    "[key] is optional. This is the cypher key or path to search for."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    item_key = args[0]
    begin
      params.merge!(parse_list_options(options))
      @cypher_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cypher_interface.dry.list(item_key, params)
        return 0
      end
      json_response = @cypher_interface.list(item_key, params)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response], options)
        return 0
      end
      cypher_items = json_response["cypherItems"] || json_response["cyphers"]
      cypher_data = json_response["data"]
      title = "Morpheus Cypher Key List"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if item_key
        subtitles << "Key: #{item_key}"
      end
      print_h1 title, subtitles, options

      cypher_keys = json_response["data"] ? json_response["data"]["keys"] : []
      if cypher_keys.nil? || cypher_keys.empty?
        if item_key
          print cyan,"No cypher items found for '#{item_key}'.",reset,"\n"
        end
      else

        cypher_columns = {
          "KEY" => lambda {|it| it["itemKey"] },
          # "LEASE REMAINING" => lambda {|it| 
          #   format_lease_remaining(it["expireDate"])
          # },
          "TTL" => lambda {|it| 
            format_expiration_ttl(it["expireDate"])
          },
          "EXPIRATION" => lambda {|it| 
            format_expiration_date(it["expireDate"])
          },
          # "DATE CREATED" => lambda {|it| format_local_dt(it["dateCreated"]) },
          "LAST UPDATED" => lambda {|it| format_local_dt(it["lastUpdated"]) },
          "LAST ACCESSED" => lambda {|it| format_local_dt(it["lastAccessed"]) }
        }
        print cyan
        print as_pretty_table(cypher_items, cypher_columns, options)
        print reset
        # print_results_pagination({size:cypher_keys.size,total:cypher_keys.size.to_i})
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
    params = {}
    value_only = false
    do_decrypt = false
    ttl = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      # opts.on(nil, '--decrypt', 'Display the decrypted value') do
      #   do_decrypt = true
      # end
      # opts.on(nil, '--metadata', 'Display metadata about the key, such as versions.') do
      #   display_versions = true
      # end
      opts.on('-v', '--value', 'Print only the decrypted value.') do
        value_only = true
      end
      opts.on( '-t', '--ttl SECONDS', "Time to live, the lease duration before this key expires. Use if creating new key." ) do |val|
        ttl = val
        if val.to_s.empty? || val.to_s == '0'
          ttl = 0
        else
          ttl = val
        end
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :outfile, :dry_run, :quiet, :remote])
      opts.footer = "Read a cypher item and display the decrypted value." + "\n" +
                    "[key] is required. This is the cypher key to read." + "\n" +
                    "Use --ttl to specify a ttl if expecting cypher engine to automatically create the key."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      item_key = args[0]
      if ttl
        params["ttl"] = ttl
      end
      @cypher_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cypher_interface.dry.get(item_key, params)
        return 0
      end
      params.merge!(parse_list_options(options))
      json_response = @cypher_interface.get(item_key, params)
      render_result = render_with_format(json_response, options)
      if render_result
        return 0
      end
      
      cypher_item = json_response['cypher']
      decrypted_value = json_response["data"]
      data_type = decrypted_value.is_a?(String) ? 'string' : 'object'

      if value_only
        print cyan
        if decrypted_value.is_a?(Hash)
          puts as_json(decrypted_value)
        else
          puts decrypted_value.to_s
        end
        print reset
        return 0
      end

      print_h1 "Cypher Key", [], options
      print cyan
      # This response does contain cypher too though.
      
      if cypher_item.empty?
        puts_error "Cypher data not found in response"
        return 1
      end
      description_cols = {
        #"ID" => 'id',
        "Key" => lambda {|it| it["itemKey"] },
        "TTL" => lambda {|it| 
          format_expiration_ttl(it["expireDate"])
        },
        # "Type" => lambda {|it| 
        #   data_type
        # },
        "Expiration" => lambda {|it| 
          format_expiration_date(it["expireDate"])
        },
        # "Date Created" => lambda {|it| format_local_dt(it["dateCreated"]) },
        "Last Updated" => lambda {|it| format_local_dt(it["lastUpdated"]) },
        "Last Accessed" => lambda {|it| format_local_dt(it["lastAccessed"]) }
      }
      if cypher_item["expireDate"].nil?
        description_cols.delete("Expires")
      end
      print_description_list(description_cols, cypher_item)

      # print_h2 "Value", options
      # print_h2 "Data", options
      print_h2 "Data (#{data_type})", options
      
      if decrypted_value
        print cyan
        if decrypted_value.is_a?(String)
          # attempt to parse and render as_json
          if decrypted_value.to_s[0] == '{' && decrypted_value.to_s[-1] == '}'
            begin
              json_value = JSON.parse(decrypted_value)
              puts as_json(json_value)
            rescue => ex
              Morpheus::Logging::DarkPrinter.puts "Failed to parse cypher value '#{decrypted_value}' as JSON. Error: #{ex}" if Morpheus::Logging.debug?
              puts decrypted_value
            end
          else
            puts decrypted_value
          end
        else
          puts as_json(decrypted_value)
        end
      else
        puts "No data found."
      end
      
      print reset, "\n"

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def put(args)
        usage = <<-EOT
Usage: morpheus #{command_name} put [key] [value] [options] to store a string.
       morpheus #{command_name} put [key] [k=v] [k=v] [options] to store an object.
EOT
    options = {}
    params = {}
    item_key = nil
    item_value = nil
    ttl = nil
    no_overwrite = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      # opts.banner = subcommand_usage("[key] [value]\n\t[key] [k=v] [k=v] [k=v]") 
      opts.banner = usage 
      opts.on( '--key KEY', String, "Key. This can also be passed as the first argument." ) do |val|
        item_key = val
      end
      opts.on( '-v', '--value VALUE', "Secret value. This can be used to store a string instead of an object, and can also be passed as the second argument." ) do |val|
        item_value = val
      end
      # opts.on( '--type VALUE', String, "Type, default is based on key engine, string or object" ) do |val|
      #   params['type'] = val
      # end
      opts.on( '-t', '--ttl SECONDS', "Time to live, the lease duration before this key expires." ) do |val|
        ttl = val
        if val.to_s.empty? || val.to_s == '0'
          ttl = 0
        else
          ttl = val
        end
      end
      # opts.on( '--no-overwrite', '--no-overwrite', "Do not overwrite existing keys. Existing keys are overwritten by default." ) do
      #   params['overwrite'] = false
      # end
      build_common_options(opts, options, [:auto_confirm, :options, :payload, :query, :json, :yaml, :csv, :fields, :outfile, :dry_run, :quiet, :remote])
      opts.footer = "Create or update a cypher key." + "\n" +
                    "[key] is required. This is the key of the cypher being created or updated. The key includes the mount prefix eg. secret/hello" + "\n" +
                    "[value] is required for some cypher engines, such as secret. This is the secret value or k=v pairs being stored. Supports 1-N arguments." + "\n" +
                    "If a single [value] is passed, it is stored as type string." + "\n" +
                    "If more than one [value] is passed, the format is expected to be k=v and the value will be stored as an object." + "\n" +
                    "The --value option can be used to store a string value." + "\n" +
                    "The --payload option can be used to store an object."
    end
    optparse.parse!(args)
    # if args.count < 1
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "wrong number of arguments, expected 1-N and got #{args.count}\n#{optparse}"
    #   return 1
    # end
    connect(options)
    params.merge!(parse_query_options(options))

    # parse arguments like [value] or [k=v]
    if args.count == 0
      # prompt for key and value
    elsif args.count == 1
      item_key = args[0]
      # prompt for value
    elsif args.count == 2
      item_key = args[0]
      item_value = args[1]
      # expecting [value] or [k=v]
      item_value_object = {}
      item_value_pair = item_value.split("=")
      if item_value_pair.size == 2
        item_value_object[item_value_pair[0].to_s] = item_value_pair[1]
        item_value = item_value_object
      else
        # item_value = item_value
      end
    elsif args.count > 2
      item_key = args[0]
      item_value = args[1]
      # expecting [k=v] [k=v]
      item_value_object = {}
      args[1..(args.size-1)].each do |arg|
        item_value_pair = arg.split("=")
        item_value_object[item_value_pair[0].to_s] = item_value_pair[1]
      end
      item_value = item_value_object
    end

    # this is redunant and silly, refactor soon

    # Key prompt
    if item_key
      options[:options]['key'] = item_key
    end
    if item_key.nil?
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'key', 'fieldLabel' => 'Key', 'type' => 'text', 'required' => true, 'description' => cypher_key_help}], options[:options])
      item_key = v_prompt['key']
    end

    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) || ['key','value'].include?(k)}) if options[:options] && options[:options].keys.size > 0
    else
      # merge -O options into normally parsed options
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) || ['key','value'].include?(k)}) if options[:options] && options[:options].keys.size > 0
      
      # Value prompt
      value_is_required = false
      cypher_mount_type = item_key.split("/").first
      if ["secret","tfvars"].include?(cypher_mount_type)
        value_is_required = true
      end

      # todo: read value from STDIN shall we?

      # cool, we got value as arguments like foo=bar
      if args.count > 1
        # parse one and only arg as the value like password/mine mypassword123
        if args.count == 2 && args[1].split("=").size() == 1
          item_value = args[1]
        elsif args.count > 1
          # parse args as key value pairs like secret/config foo=bar thing=myvalue
          value_arguments = args[1..-1]
          value_arguments_map = {}
          value_arguments.each do |value_argument|
            value_pair = value_argument.split("=")
            value_arguments_map[value_pair[0]] = value_pair[1] ? value_pair[1..-1].join("=") : nil
          end
          item_value = value_arguments_map
        end
      else
        # Prompt for a single text value to be sent as {"value":"my secret"}
        if value_is_required
          options[:options]['value'] = item_value if item_value
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'value', 'fieldLabel' => 'Value', 'type' => 'text', 'required' => value_is_required, 'description' => "Secret value for this cypher"}], options[:options])
          item_value = v_prompt['value']
        end
      end

      # make sure not to pass a value for these or it will not save them.
      # if ['uuid','key','password'].include?(cypher_mount_type)
      #   item_value = nil
      # end

      # construct payload
      # payload = {
      #   'cypher' => params
      # }
      payload = {}
      # if value is valid json, then the payload IS the value
      if item_value.is_a?(String) && item_value.to_s[0] == '{' && item_value.to_s[-1] == '}'
        begin
          json_object = JSON.parse(item_value)
          item_value = json_object
        rescue => ex
          Morpheus::Logging::DarkPrinter.puts "Failed to parse cypher value '#{item_value}' as JSON. Error: #{ex}" if Morpheus::Logging.debug?
          raise_command_error "Failed to parse cypher value as JSON: #{item_value}"
          # return 1
        end
      else
        # it is just a string
        if item_value.is_a?(String)
          params['type'] = 'string'
          #params["value"] = item_value
          payload["value"] = item_value
        elsif item_value.nil?
          payload = {}
        else item_value
          # great, a Hash I hope
          payload = item_value
        end
      end
    end

    # prompt for Lease
    options[:options]['ttl'] = ttl if ttl
    v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ttl', 'fieldLabel' => 'Lease (TTL in seconds)', 'type' => 'text', 'required' => false, 'description' => cypher_ttl_help, 'defaultValue' => '0'}], options[:options])
    ttl = v_prompt['ttl']

    if ttl
      params['ttl'] = ttl
      #payload["ttl"] = ttl
    end
    @cypher_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @cypher_interface.dry.create(item_key, params, payload)
      return
    end
    existing_cypher = nil
    json_response = @cypher_interface.list(item_key)
    if json_response["data"] && json_response["data"]["keys"]
      existing_cypher = json_response["data"]["keys"].find {|k| k == item_key }
    end
    if existing_cypher
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to overwrite the cypher key #{item_key}?")
        return 9, "aborted command"
      end
    end
    json_response = @cypher_interface.create(item_key, params, payload)
    render_result = render_with_format(json_response, options)
    if render_result
      return 0
    end
    #print_green_success "Cypher #{item_key} updated"
    # print_green_success "Wrote cypher #{item_key}"
    print_green_success "Success! Data written to: #{item_key}"
    # should print without doing get, because that can use a token.
    cypher_item = json_response['cypher']
    get_args = [item_key] + (options[:remote] ? ["-r",options[:remote]] : [])
    get(get_args)
    return 0
  end
  
  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a cypher." + "\n" +
                    "[key] is required. This is the cypher key to be deleted."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      item_key = args[0]
      cypher_item = find_cypher_by_key(item_key)
      return 1 if cypher_item.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cypher #{item_key}?")
        return 9, "aborted command"
      end
      @cypher_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cypher_interface.dry.destroy(item_key, params)
        return
      end
      json_response = @cypher_interface.destroy(item_key, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted cypher #{item_key}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

  def find_cypher_by_key(key, params={})
    begin
      json_response = @cypher_interface.get(key, params)
      return json_response
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Cypher not found by key #{key}"
        return nil
      else
        raise e
      end
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

  def cypher_ttl_help
    """
TTL in seconds
Quick Second Time Reference:
Hour: 3600
Day: 86400
Week: 604800
Month (30 days): 2592000
Year: 31536000
Unlimited: 0
This can be passed in abbreviated duration format. eg. 32d, 90s, 5y
The default is 0, meaning Unlimited.
"""
  end

  def format_lease_remaining(expire_date, warning_threshold=3600, return_color=cyan)
    out = ""
    if expire_date
      out << format_expiration_date(expire_date, warning_threshold, return_color)
      out << " ("
      out << format_expiration_ttl(expire_date, warning_threshold, return_color)
      out << ")"
    else
      # out << return_color
      out << "Never expires"
    end
    return out
  end

  def format_expiration_date(expire_date, warning_threshold=3600, return_color=cyan)
    expire_date = parse_time(expire_date)
    if !expire_date
      # return ""
      return cyan + "Never expires" + return_color
    end
    if expire_date <= Time.now
      return red + format_local_dt(expire_date) + return_color
    else
      return cyan + format_local_dt(expire_date) + return_color
    end
  end

  def format_expiration_ttl(expire_date, warning_threshold=3600, return_color=cyan)
    expire_date = parse_time(expire_date)
    if !expire_date
      return ""
      #return cyan + "Never expires" + return_color
    end
    seconds = expire_date - Time.now
    if seconds <= 0
      # return red + "Expired" + return_color
      return red + "Expired " + format_duration_seconds(seconds.abs).to_s + " ago" + return_color
    elsif seconds <= warning_threshold
      return yellow + format_duration_seconds(seconds.abs).to_s + return_color
    else
      return cyan + format_duration_seconds(seconds.abs).to_s + return_color
    end
  end
end

