require 'morpheus/cli/cli_command'

# JD: this is not in use, we have login, logout and access-token instead
# This provides commands for authentication 
# This also includes credential management.
class Morpheus::Cli::AuthCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'auth'

  register_subcommands :get
  # register_subcommands :list # yes plz
  # register_subcommands :'access-token' => :print_access_token
  # register_subcommands :'refresh-token' => :print_refresh_token
  # register_subcommands :'use-refresh-token' => :use_refresh_token
  register_subcommands :login, :logout
  register_subcommands :test => :login_test

  def connect(options)
    @api_client = establish_remote_appliance_connection(options.merge({:no_prompt => true, :skip_verify_access_token => true, :skip_login => true}))
    # automatically get @appliance_name, @appliance_url, @wallet
    if !@appliance_name
      raise_command_error "#{command_name} requires a remote to be specified, use -r [remote] or set the active remote with `remote use`"
    end
    if !@appliance_url
      unless options[:quiet]
        print red,"Unable to determine remote appliance url. Review your remote configuration.#{reset}\n"
      end
      return 1
    end
    #@wallet = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
    if @wallet.nil? || @wallet['access_token'].nil?
      unless options[:quiet]
        print_error yellow,"You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
        print_error yellow,"Use `login` to authenticate.",reset,"\n"
      end
      return 1
    end
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:remote, :quiet])
      opts.footer = "Print your current authentication info.\n" +
                    "This contains tokens that should be kept secret, be careful."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect_result = connect(options)
    return connect_result if (connect_result.is_a?(Numeric) && connect_result != 0)
  
    # could fetch and show whoami info as well eh?
    # extra api call though..

    #print_h1 "Morpheus Credentials", [display_appliance(@appliance_name, @appliance_url)], options
    print_h1 "Morpheus Credentials", [], options
    description_cols = {
      "Remote" => lambda {|wallet| @appliance_name },
      "Username" => lambda {|wallet| wallet['username'] },
      "Access Token" => lambda {|wallet| wallet['access_token'] },
      "Refresh Token" => lambda {|wallet| wallet['refresh_token'] },
      "Login Date" => lambda {|wallet| format_local_dt(wallet['login_date']) },
      "Expire Date" => lambda {|wallet| wallet['expire_date'] ? format_local_dt(wallet['expire_date']) : "" },
    }
    print cyan
    puts as_description_list(@wallet, description_cols)
    print reset
    return 0
  end
  
  # these are all just aliases, heh

  def login(args)
    ::Morpheus::Cli::Login.new.handle(args)
  end

  def login_test(args)
    ::Morpheus::Cli::Login.new.handle(['--test'] + args)
  end

  def logout(args)
    ::Morpheus::Cli::Logout.new.handle(args)
  end

  def print_access_token(args)
    ::Morpheus::Cli::AccessTokenCommand.new.handle(args)
  end

  def use_refresh_token(args)
    ::Morpheus::Cli::AccessTokenCommand.new.handle(['refresh'] + args)
  end


  protected

end
