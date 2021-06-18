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
    # @api_client = establish_remote_appliance_connection({:skip_verify_access_token => true, :skip_login => true}.merge(opts))
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
      opts.on( '-u', '--username USERNAME', "Username. Sub-tenant users must format their username with a prefix like {subdomain}\\{username}" ) do |val|
        username = val
      end
      opts.on( '-p', '--password PASSWORD', "Password" ) do |val|
        password = val
      end
      opts.on( '--password-file FILE', String, "Password File, read a file containing the password." ) do |val|
        password_file = File.expand_path(val)
        if !File.exists?(password_file) || !File.file?(password_file) # check readable too
          raise ::OptionParser::InvalidOption.new("File not found: #{password_file}")
        end
        password = File.read(password_file) #.to_s.split("\n").first.strip
      end
      opts.on( '-t', '--test', "Test credentials only, does not update stored credentials for the appliance." ) do
        options[:test_only] = true
      end
      opts.on( '--client-id CLIENT', "Used to test authentication with a client_id other than #{Morpheus::APIClient::CLIENT_ID}. Currently behaves like --test, credentials are not stored." ) do |val|
        options[:client_id] = val.to_s
        options[:test_only] = true
      end
      opts.on( '-T', '--token ACCESS_TOKEN', "Use an existing access token to login instead of authenticating with a username and password." ) do |val|
        options[:remote_token] = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet], [:remote_username, :remote_password, :remote_token])
      opts.footer = <<-EOT
Login to a remote appliance with a username and password or using an access token.
Logging in with username and password will make an authentication api request to obtain an access token.
[username] is required, this is the username of the Morpheus User
[password] is required, this is the password of the Morpheus User
Sub-tenant users will need to pass their tenant subdomain prefix. ie. {subdomain}\\{username}
By default, the subdomain is the tenant account ID. Example: 2\\neo
The --token option can be used to login with a valid access token instead of username and password.
The specified token will be verified by making a whoami api request
If successful, the access token will be saved with the active session for the remote appliance.
This command will first logout any active session before attempting authentication.
The --test option can be used to test credentials without updating the stored credentials for the appliance, neither logging you in or out.
EOT
                    
    end
    optparse.parse!(args)
    verify_args!(args:args, max:2, optparse:optparse)
    username = args[0] if args[0]
    password = args[1] if args[1]
    
    # connect(options)
    @api_client = establish_remote_appliance_connection(options.merge({:no_prompt => true, :skip_verify_access_token => true, :skip_login => true}))
    
    if options[:test_only]
      puts "Testing credentials, your current session will not be modified."
    elsif @remote_appliance[:authenticated]
      puts "You will be automatically logged out of your current session as '#{@remote_appliance[:username]}'"
    end

    begin
      if (options[:quiet] && (!options[:remote_token]) && !(username && password))
        print_error yellow,"Please specify username and password, or token.", reset, "\n"
        return 1
      end

      options[:username] = username if username
      options[:password] = password if password

      do_save = true
      if options[:test_only] || options[:remote_url]
        do_save = false
      end
      #old_wallet = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
      
      login_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(options, do_save)
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
            print green,"Success! Test Credentials verified for #{wallet['username']}", reset, "\n"
          else
            # clear whoami cache, it will be lazily load_saved_credentials
            ::Morpheus::Cli::Whoami.clear_whoami(@appliance_name, wallet['username'])
            print green,"Success! Logged in as #{wallet['username']}", reset, "\n"
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
            # if old_wallet && old_wallet['access_token']
            #   #print reset,"You are no longer logged in. Goodbye #{old_wallet['username']}!", reset, "\n"
            #    # todo: prompt to recover wallet ?
            # end
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
