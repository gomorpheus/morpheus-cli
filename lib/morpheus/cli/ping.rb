# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/whoami_helper'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Ping
  include Morpheus::Cli::CliCommand

  set_command_name :ping

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts.merge({:no_prompt => true, :skip_verify_access_token => true}))
    @ping_interface = @api_client.ping
  end

  def handle(args)
    exit_code, err = 0, nil
    params, options = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      build_standard_get_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Ping the remote morpheus appliance.
Prints the build returned information, Build Version and Appliance URL.
EOT
      build_common_options(opts, options, [:json, :remote, :dry_run, :quiet])
    end
    optparse.parse!(args)
    connect(options)
    begin
      # construct parameters
      params.merge!(parse_query_options(options))

      # error if we could not determine a remote
      if !@appliance_name
        # never gets here..
        #raise_command_error "Please specify a Morpheus Appliance with -r or see the command `remote use`"
        print yellow,"Please specify a Morpheus Appliance with -r or see `remote use`.#{reset}\n"
        return 1, "command requires a remote appliance"
      end
      
      # set api client options
      @api_client.setopts(options)

      # dry run, print the would be request
      if options[:dry_run]
        print_dry_run @ping_interface.dry.get(params)
        return 0
      end

      # execute the api request
      json_response = @ping_interface.get(params)
      
      # render with standard formats like json,yaml,csv and quiet
      render_result = render_with_format(json_response, options)
      return exit_code, err if render_result

      # print output
      print_h1 "Morpheus Ping", [["[#{@appliance_name}] #{@appliance_url}"]], options
      print cyan
      print_description_list({
        # "Remote" => lambda {|it| appliance_name },
        "Build Version" => lambda {|it| it['buildVersion'] },
        "Appliance URL" => lambda {|it| it['applianceUrl'] },
      }, json_response, options)
      print reset, "\n"
      # always return result exit code and err, hopefully 0, nil
      return exit_code, err
    rescue RestClient::Exception => e
      print_red_alert("ping failed")
      #print_error red,"ping failed",reset,"\n"
      print_rest_exception(e, options)
      return 1, e.message
    end
  end

end
