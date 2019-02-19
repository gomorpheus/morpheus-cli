# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/remote'
require 'morpheus/cli/credentials'
require 'json'

class Morpheus::Cli::Logout
  include Morpheus::Cli::CliCommand
  # include Morpheus::Cli::WhoamiHelper
  # include Morpheus::Cli::AccountsHelper
  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    #@api_client = establish_remote_appliance_connection(opts)
  end

  def usage
    "Usage: morpheus logout"
  end

  def handle(args)
    logout(args)
  end

  def logout(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      build_common_options(opts, options, [:remote, :quiet])
    end
    optparse.parse!(args)
    # connect(options)
    # establish @appliance_name, @appliance_url, 
    @api_client = establish_remote_appliance_connection(options.merge({:no_prompt => true, :skip_verify_access_token => true}))

    begin
      if !@appliance_name
        print_error Morpheus::Terminal.angry_prompt
        puts_error "Please specify a Morpheus Appliance to logout of with -r or see the command `remote use`"
        return 1
      end
      wallet = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials
      token = wallet ? wallet['access_token'] : nil
      if !token
        if !options[:quiet]
          puts "You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}"
        end
      else
        # todo: need to tell the server to delete the token too..
        # delete token from credentials file
        # note: this also handles updating appliance session info
        Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).logout()
        if !options[:quiet]
          puts "#{cyan}Logged out of #{@appliance_name}. Goodbye #{wallet['username']}!#{reset}"
        end
      end
      # recalcuate echo vars
      Morpheus::Cli::Echo.recalculate_variable_map()
      # recalculate shell prompt after this change
      if Morpheus::Cli::Shell.has_instance?
        Morpheus::Cli::Shell.instance.reinitialize()
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end

  end


end
