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
    "Usage: morpheus login [username] [password]"
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
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet], [:username, :password, :remote_token])
      opts.footer = "Login to a remote appliance with username and password or an access token.\n" +
                    "[username] is required and will be prompted for if not given.\n" +
                    "[password] is required and will be prompted for if not given.\n" +
                    "The --token option can be used to login with an existing token instead of [username] and [password].\n" +
                    "Logging in with username and password will make an authentication api request to obtain an access token.\n" +
                    "If using --token, the whoami api is used to validate the token.\n" +
                    "If successful, the access token will be saved with the active session for the remote appliance, for use with future commands.\n" +
                    "This command will first logout any active session before attempting to login." + 
                    "The --test option allows for authenticating credentials without updating your active session."
                    
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
        return 1
      end
    else
      @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
      if !@appliance_name
        print_error yellow, "Please specify a remote appliance with -r or see the command `remote use`", reset, "\n"
        return 1
      end
    end

    begin
      if (options[:quiet] && (!options[:remote_token]) && !(username && password))
        print_error yellow,"Please specify username and password, or token.", reset, "\n"
        return 1
      end

      options[:username] = username if username
      options[:password] = password if password


      # ok, what we should really do is prompt to add the remote on the fly
      # fuck ya!

      # load existing credentials (without erroring)
      # this is so we can tell you you're getting automatically logged out.
      # maybe it should not ever log you out unless it succeeds (and overwrites your current session)
      # old_wallet = @wallet
      old_wallet = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
      if old_wallet && old_wallet['access_token'] && options[:test_only] != true
        unless options[:quiet]
          print reset,"You have been automatically logged out. Goodbye #{old_wallet['username']}!", reset, "\n"
        end
      end
      login_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(options)
      if options[:dry_run]
        return 0
      end
      wallet = login_result

      # needed here too?
      ::Morpheus::Cli::Remote.recalculate_variable_map()

      # should happen here, not in Credentials.login()
      # if options[:json]
      #   puts as_json(login_result)
      #   return (login_result && login_result['access_token']) ? 0 : 1
      # end

      if wallet && wallet['access_token']
        # Login Success!
        if !options[:quiet]
          if options[:test_only]
            print green,"Success! Credentials verified for #{wallet['username']}.", reset, "\n"
          else
            print green,"Success! Logged in to #{@appliance_name} as #{wallet['username']}.", reset, "\n"
          end
        end
        return 0 # ,  nil
      else
        # Login Failed
        # so login() already prints 'Bad Credentials' (deprecate class Credentials plz)
        # tell them if they're logged out now.
        if !options[:quiet]
          if options[:test_only]
            # you are fine, nothing has changed
          else
            if old_wallet && old_wallet['access_token']
              #print reset,"You are no longer logged in. Goodbye #{old_wallet['username']}!", reset, "\n"
               # todo: prompt to recover wallet ?
            end
          end
        end
        return 1, "Login failed"
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end

  end


end
