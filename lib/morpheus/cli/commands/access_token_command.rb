require 'morpheus/cli/cli_command'

# This provides commands for authentication 
# This also includes credential management.
class Morpheus::Cli::AccessTokenCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'access-token'
  #set_command_name :'access'
  register_subcommands :get => :print_access_token
  register_subcommands :details => :details
  register_subcommands :refresh => :use_refresh_token

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  # connect overridden to skip login and return an exit_code
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
        print_error yellow,"Use `login` to authenticate or try passing the --username option.",reset,"\n"
      end
      return 1
    end
    return 0
  end

  def handle(args)
    # access-token get by default, except access-token -h should list the subcommands.
    if args.empty? || (args[0] && args[0] =~ /^\-/ && !['-h', '--help'].include?(args[0]))
      print_access_token(args)
    else
      handle_subcommand(args)
    end
  end

  def details(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:remote, :quiet])
      opts.footer = "Print your current authentication credentials.\n" +
                    "This contains tokens that should be kept secret. Be careful."
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
    print_h1 "Morpheus Credentials", options
    description_cols = {
      "Username" => lambda {|wallet| wallet['username'] },
      "Access Token" => lambda {|wallet| wallet['access_token'] },
      "Refresh Token" => lambda {|wallet| wallet['refresh_token'] },
      "Login Date" => lambda {|wallet| format_local_dt(wallet['login_date']) },
      "Expire Date" => lambda {|wallet| wallet['expire_date'] ? format_local_dt(wallet['expire_date']) : "" },
      # "Remote" => lambda {|wallet| display_appliance(@appliance_name, @appliance_url) },
    }
    print cyan
    puts as_description_list(@wallet, description_cols)
    print reset
    return 0
  end

  def print_access_token(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:remote, :quiet])
      opts.footer = "Print your current access token.\n" +
                    "This token should be kept secret. Be careful."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect_result = connect(options)
    return connect_result if (connect_result.is_a?(Numeric) && connect_result != 0)
    unless options[:quiet]
      print cyan
      puts @wallet['access_token']
      print reset
    end
    return @wallet['access_token'] ? 0 : 1
  end

  def use_refresh_token(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-T', '--token TOKEN', "Refresh Token to use. The saved credentials are used by default." ) do |val|
        options[:refresh_token] = val
      end
      opts.on( '--token-file FILE', String, "Refresh Token File, read a file containing the refresh token." ) do |val|
        token_file = File.expand_path(val)
        if !File.exists?(token_file) || !File.file?(token_file)
          raise ::OptionParser::InvalidOption.new("File not found: #{token_file}")
        end
        options[:refresh_token] = File.read(token_file).to_s.split("\n").first.strip
      end
      build_common_options(opts, options, [:auto_confirm, :remote, :dry_run, :json, :quiet], [:remote_username, :remote_password, :remote_token])
      opts.footer = "Use the refresh token in your saved credentials, or a provided token.\n" +
                    "This will replace your current access and refresh tokens with a new values.\n" +
                    "Your current access token will be invalidated\n" +
                    "All other users or applications with access to your token will need to update to the new token."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end

    connect_result = connect(options)
    return connect_result if (connect_result.is_a?(Numeric) && connect_result != 0)
    # if @wallet.nil? || @wallet['access_token'].nil?
    #   unless options[:quiet]
    #     print_error yellow,"You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
    #     print_error yellow,"Use `login` to authenticate or try passing the --username option.",reset,"\n"
    #   end
    #   return 1
    # end
    refresh_token_value = nil
    if options[:refresh_token]
      refresh_token_value = options[:refresh_token]
    else
      if @wallet['refresh_token']
        refresh_token_value = @wallet['refresh_token']
      else
        unless options[:quiet]
          print_error yellow,"No refresh token found for appliance #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
          print_error yellow,"Use the 'login' command.",reset,"\n"
        end
        return 1
      end
    end
    if options[:dry_run]
      print_dry_run @api_client.auth.dry.use_refresh_token(refresh_token_value)
      return 0
    end
    unless options[:quiet]
      access_token = @wallet['access_token'].to_s
      visible_part = access_token[0..7]
      if visible_part
        masked_access_token = visible_part + access_token[8..-1].gsub(/[^-]/, '*')
      else
        masked_access_token = access_token.gsub(/[^-]/, '*')
      end
      print cyan,"#{bold}WARNING!#{reset}#{cyan} You are about to invalidate your current access token '#{masked_access_token}'.",reset,"\n"
      print cyan, "You will need to update everywhere this token is used.",reset, "\n"
    end
    
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to refresh your access token?")
      return 9, "aborted command"
    end

    # ok, let's use our refresh token
    # this regenerates the current access token.
    refresh_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).use_refresh_token(refresh_token_value, options)
    new_wallet = refresh_result
    if options[:json]
      puts as_json(refresh_result, options)
      return new_wallet ? 0 : 1
    end
    if new_wallet
      unless options[:quiet]
        print_green_success "Access token refreshed: #{new_wallet['access_token']}"
        #print_green_success "Access token refreshed"
        details([])
      end
      return 0
    else
      print_red_alert "Failed to use refresh token."
      return 1
    end
  end

  protected

end
