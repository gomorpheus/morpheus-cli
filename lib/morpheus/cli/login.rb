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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on( '-u', '--username USERNAME', "Username" ) do |val|
        username = val
      end
      opts.on( '-p', '--password PASSWORD', "Password" ) do |val|
        password = val
      end
      opts.on( '-t', '--test', "Test credentials only, does not update stored credentials for the appliance." ) do
        options[:test_only] = true
      end
      opts.on( '-T', '--token ACCESS_TOKEN', "Use an existing access token instead of authenticating with a username and password." ) do |val|
        options[:remote_token] = val
      end
      build_common_options(opts, options, [:json, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} list expects 0-2 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    username = args[0] if args[0]
    password = args[1] if args[1]
    
    # connect(options)
    if options[:remote]
      appliance = Morpheus::Cli::Remote.appliances[options[:remote].to_sym]
      if appliance
        @appliance_name, @appliance_url = options[:remote].to_sym, appliance[:host]
      else
        @appliance_name, @appliance_url = nil, nil
      end
      if !@appliance_name
        print_error red, "You have no appliance named '#{options[:remote]}' configured. See the `remote list` command.", reset, "\n"
        return false
      end
    else
      @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
      if !@appliance_name
        print_error yellow, "Please specify a remote appliance with -r or see the command `remote use`", reset, "\n"
        return false
      end
    end

    begin
      if options[:quiet]
        if ((!options[:remote_token]) && !(username && password))
          print_error yellow,"Please specify a username and password, or token.", reset, "\n"
          return false
        end
      end
      options[:remote_username] = username if username
      options[:remote_password] = password if password
      #options[:remote_url] = true # will skip credentials save
      login_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(options)
      # check to see if we got credentials, or just look at login_result above...
      #creds = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials() # .load_saved_credentials(true)
      if login_result
        creds = login_result
      end
      

      # recalcuate echo vars
      ::Morpheus::Cli::Remote.recalculate_variable_map()

      if creds
        if !options[:quiet]
          if options[:test_only]
            print green,"Valid credentials for user #{username}", reset, "\n"
          else
            print green,"Logged in to #{@appliance_name} as #{::Morpheus::Cli::Remote.load_remote(@appliance_name)[:username]}#{reset}", reset, "\n"
          end
        end
        return 0 # ,  nil
      else
        return 1 # , "Login failed"
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end

  end


end
