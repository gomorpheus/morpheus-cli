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
    #@access_token = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials(options)
  end

  def usage
    "Usage: morpheus logout"
  end

  def handle(args)
    logout(args)
  end

  def logout(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      build_common_options(opts, options, [:remote]) # todo: support :remote too perhaps
    end
    optparse.parse!(args)
    connect(options)

    begin
      if !@appliance_name
        print yellow,"Please specify a Morpheus Appliance to logout of with -r or see the command `remote use`#{reset}\n"
        return
      end
      creds = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
      if !creds
        print yellow,"You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}\n",reset
        return 0
      else
        Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).logout()
        print cyan,"Goodbye\n",reset
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end

  end


end
