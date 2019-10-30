require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::License
  include Morpheus::Cli::CliCommand

  register_subcommands :get, :install, :uninstall, :test
  # deprecated
  register_subcommands :decode, :apply
  #alias_subcommand :details, :get

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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :yaml, :fields, :dry_run, :remote])
      opts.footer = "Get details about the currently installed license.\n" +
                    "This information includes license features and limits.\n" +
                    "The actual secret license key value will never be returned."
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      # make api request
      @license_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @license_interface.dry.get()
        return 0, nil
      end
      json_response = @license_interface.get()
      # 200 OK, parse results
      license = json_response['license']
      used_memory = json_response['licenseUsedMemory']
      
      # Determine exit status and any error conditions for the command
      exit_code = 0
      err = nil
      if license.nil?
        exit_code = 1
        err = "No license currently installed."
      end

      # render common formats like dry run, curl, json , yaml , etc.
      render_result = render_with_format(json_response, options)
      return exit_code, err if render_result

      if options[:quiet]
        return exit_code, err
      end
      
      # if exit_code != 0 
      #   print_error red, err.to_s, reset, "\n"
      #   return exit_code, err
      # end
      
      # render output

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
        "End Date" => lambda {|it| 
          if it['endDate']
            format_local_dt(it['endDate']).to_s + ' (' + format_duration(Time.now, it['endDate']).to_s + ')' 
          else
            'None'
          end
          },
        "Memory" => lambda {|it| "#{used_memory} / #{max_memory}" },
        "Max Storage" => lambda {|it| "#{max_storage}" },
        "Max Instances" => lambda {|it| it["maxInstances"].to_i == 0 ? 'Unlimited' : it["maxInstances"] },
        "Hard Limit" => lambda {|it| it[""] == false ? 'Yes' : 'No' },
      }
      print_description_list(description_cols, license)
      print reset,"\n"
    
    return exit_code, err
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
  end

  def apply(args)
    print_error "#{yellow}DEPRECATION WARNING: `license apply` has been deprecated and replaced with `license install`. Please use `license install` instead.#{reset}\n"
    install(args)
  end

  def install(args)
    options = {}
    account_name = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      if args[0]
        key = args[0]
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'required' => true}], options[:options])
        key = v_prompt['licenseKey'] || ''
      end
      @license_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @license_interface.dry.install(key)
        return 0
      end
      json_response = @license_interface.install(key)
      license = json_response['license']
      if options[:json]
        puts JSON.pretty_generate(json_response)
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
    print_error "#{yellow}DEPRECATION WARNING: `license decode` has been deprecated and replaced with `license test`. Please use `license test` instead.#{reset}\n"
    test(args)
  end

  def test(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Test a license key.\n" +
                    "This is a way to decode and view a license key before installing it."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    key = nil
    if args[0]
      key = args[0]
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'required' => true}], options[:options])
      key = v_prompt['licenseKey'] || ''
    end
    begin
      @license_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @license_interface.dry.test(key)
        return
      end
      json_response = @license_interface.test(key)
      license = json_response['license']

      exit_code, err = 0, nil
      if license.nil?
        err = "Unable to decode license."
        exit_code = 1
        #return err, exit_code
      end
      render_result = render_with_format(json_response, options)
      if render_result
        return exit_code, err
      end
      if options[:quiet]
        return exit_code, err
      end
      if exit_code != 0
        print_error red, err.to_s, reset, "\n"
        return exit_code, err
      end
      
      # all good
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
      return exit_code, err
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def uninstall(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[key]")
      build_common_options(opts, options, [:auto_confirm, :json, :yaml, :dry_run, :remote])
      opts.footer = "Uninstall the current license key.\n" +
                    "This clears out the current license key from the appliance.\n" +
                    "The function of the remote appliance will be restricted without a license installed.\n" +
                    "Be careful using this."
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      @license_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @license_interface.dry.uninstall(params)
        return
      end
      
      unless options[:quiet]
        print cyan,"#{bold}WARNING!#{reset}#{cyan} You are about to uninstall your license key.",reset,"\n"
        print yellow, "Be careful using this. Make sure you have a copy of your key somewhere if you intend to use it again.",reset, "\n"
        print "\n"
      end
      
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you want to uninstall the license key for remote #{@appliance_name} - #{@appliance_url}?")
        return 9, "command aborted"
      end

      json_response = @license_interface.uninstall(params)
      
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.wiki(app["id"], params)
        return
      end
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      return 0 if options[:quiet]
      print_green_success "License uninstalled!"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  def format_product_tier(license)
    product_tier = license['productTier'] || 'capacity'
    if product_tier == 'capacity'
      'Capacity'
    elsif product_tier == 'essentials'
      'Essentials'
    elsif product_tier == 'pro'
      'Pro'
    elsif product_tier == 'enterprise'
      'Enterprise'
    elsif product_tier == 'msp'
      'Service Provider'
    else
      product_tier.to_s.capitalize
    end
  end
end
