require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::License
  include Morpheus::Cli::CliCommand

  register_subcommands :get, :apply, :decode
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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
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
      json_result = @license_interface.get()
      license = json_result['license']
      used_memory = json_result['licenseUsedMemory']
      if options[:json]
        puts JSON.pretty_generate(json_result)
      else
        if license.nil?
          puts_error "No license currently applied to the appliance."
          return 1
        else
          print_h1 "License"
          max_memory = "Unlimited"
          max_storage = "Unlimited"
          max_memory = Filesize.from("#{license['maxMemory']} B").pretty  if license['maxMemory'].to_i != 0
          max_storage = Filesize.from("#{license['maxStorage']} B").pretty  if license['maxStorage'].to_i != 0
          used_memory = Filesize.from("#{used_memory} B").pretty if used_memory.to_i != 0
          print cyan
          description_cols = {
            "Account" => 'accountName',
            "Product Tier" => lambda {|it| format_product_tier(it) },
            "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
            "End Date" => lambda {|it| format_local_dt(it['endDate']) },
            "Memory" => lambda {|it| "#{used_memory} / #{max_memory}" },
            "Max Storage" => lambda {|it| "#{max_storage}" },
            "Max Instances" => lambda {|it| it["maxInstances"].to_i == 0 ? 'Unlimited' : it["maxInstances"] },
            "Hard Limit" => lambda {|it| it[""] == false ? 'Yes' : 'No' },
          }
          print_description_list(description_cols, license)
          print reset,"\n"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
  end

  def apply(args)
    options = {}
    account_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
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
        key = v_prompt['licenseKey'] || ''
      end
      if options[:dry_run]
        print_dry_run @license_interface.dry.apply(key)
        return 0
      end
      json_result = @license_interface.apply(key)
      license = json_result['license']
      if options[:json]
        puts JSON.pretty_generate(json_result)
      else
        print_green_success "License applied successfully!"
        # get([]) # show it
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
  end

  def decode(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Decode a license key."
    end
    optparse.parse!(args)
    connect(options)
    key = nil
    if args[0]
      key = args[0]
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'required' => true}], options[:options])
      key = v_prompt['licenseKey'] || ''
    end
    begin
      if options[:dry_run]
        print_dry_run @license_interface.dry.decode(key)
        return
      end
      json_result = @license_interface.decode(key)
      license = json_result['license']
      if options[:json]
        puts JSON.pretty_generate(json_result)
      else
        if license.nil?
          puts_error "Unable to decode license."
          puts_error json_results['msg'] if json_results['msg']
          return 1
        else
          print_h1 "License"
          max_memory = "Unlimited"
          max_storage = "Unlimited"
          max_memory = Filesize.from("#{license['maxMemory']} B").pretty  if license['maxMemory'].to_i != 0
          max_storage = Filesize.from("#{license['maxStorage']} B").pretty  if license['maxStorage'].to_i != 0
          print cyan
          description_cols = {
            "Account" => 'accountName',
            "Product Tier" => lambda {|it| format_product_tier(it) }, 
            "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
            "End Date" => lambda {|it| format_local_dt(it['endDate']) },
            "Max Memory" => lambda {|it| max_memory },
            "Max Storage" => lambda {|it| max_storage },
            "Max Instances" => lambda {|it| it["maxInstances"].to_i == 0 ? 'Unlimited' : it["maxInstances"] },
            "Hard Limit" => lambda {|it| it[""] == false ? 'Yes' : 'No' },
          }
          print_description_list(description_cols, license)
          print reset,"\n"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
  end

  def format_product_tier(license)
    product_tier = license['productTier'] || 'capacity'
    if product_tier = 'capacity'
      'Capacity'
    elsif product_tier = 'essentials'
      'Essentials'
    elsif product_tier = 'pro'
      'Pro'
    elsif product_tier = 'enterprise'
      'Enterprise'
    elsif product_tier = 'msp'
      'Service Provider'
    else
      product_tier.to_s.capitalize
    end
  end
end
