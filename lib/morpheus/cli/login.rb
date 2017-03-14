# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::Login
  include Morpheus::Cli::CliCommand
  # include Morpheus::Cli::WhoamiHelper
  # include Morpheus::Cli::AccountsHelper
  def initialize()
    
  end

  def connect(opts)
    #@api_client = establish_remote_appliance_connection(opts)
  end

  def usage
    "Usage: morpheus login"
  end

  def handle(args)
    login(args)
  end

  def login(args)
    options = {}
    username, password = nil, nil
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      opts.on( '-u', '--username USERNAME', "Username" ) do |val|
        username = val
      end
      opts.on( '-p', '--password PASSWORD', "Password" ) do |val|
        password = val
      end
      build_common_options(opts, options, [:json, :remote, :quiet])
    end
    optparse.parse!(args)

    # connect(options)
    if options[:remote]
      appliance = Morpheus::Cli::Remote.appliances[options[:remote].to_sym]
      if appliance
        @appliance_name, @appliance_url = options[:remote].to_sym, appliance[:host]
      else
        @appliance_name, @appliance_url = nil, nil
      end
      if !@appliance_name
        print_red_alert "You have no appliance named '#{options[:remote]}' configured. See the `remote add` command."
        return false
      end
    else
      @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
      if !@appliance_name
        print yellow,"Please specify a remote appliance with -r or see the command `remote use`#{reset}\n"
        return false
      end
    end

    begin
      if options[:quiet]
        if username.empty? || password.empty?
          print yellow,"You have not specified username and password\n"
          return false
        end
      end
      options[:remote_username] = username if username
      options[:remote_password] = password if password
      #options[:remote_url] = true # will skip credentials save
      Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(options)

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end

  end


end
