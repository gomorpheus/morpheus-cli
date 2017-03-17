require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::License
  include Morpheus::Cli::CliCommand

  register_subcommands :get, :apply
  alias_subcommand :details, :get

  def initialize() 
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)		
    @license_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).license
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      if options[:dry_run]
        print_dry_run @license_interface.dry.get()
        return
      end
      license = @license_interface.get()
      if options[:json]
        puts JSON.pretty_generate(license)
      else
        if license['license'].nil?
          puts "No License Currently Applied to the appliance."
          exit 1
        else
          print_h1 "License"
          max_memory = Filesize.from("#{license['license']['maxMemory']} B").pretty
          max_storage = Filesize.from("#{license['license']['maxStorage']} B").pretty
          used_memory = Filesize.from("#{license['usedMemory']} B").pretty
          puts "Account: #{license['license']['accountName']}"
          puts "Start Date: #{license['license']['startDate']}"
          puts "End Date: #{license['license']['endDate']}"
          puts "Memory: #{used_memory} / #{max_memory}"
          puts "Max Storage: #{max_storage}"
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
  end

  def apply(args)
    options = {}
    account_name = nil
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      if args[0]
        key = args[0]
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'required' => true}], options[:options])
        instance_name = v_prompt['licenseKey'] || ''
      end
      if options[:dry_run]
        print_dry_run @license_interface.dry.apply(key)
        return
      end
      license_results = @license_interface.apply(key)
      if options[:json]
        puts JSON.pretty_generate(license_results)
      else
        puts "License applied successfully!"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
  end

end
