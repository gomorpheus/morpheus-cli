require 'morpehus/cli/cli_command'

class Morpheus::Cli::ClientsCommand
	include Morpheus::Cli::CliCommand
	include Morpheus::Cli::AccountsHelper
	include Morpheus::Cli::OptionSourceHelper
	include Morpheus::Cli::LogsHelper

  set_command_name :clients
  set_command_description "View and manage Oath Clients"
  register_subcommands :list

  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clients_interface = @api_client.clients
  end

  def usage
    "Usage: morpheus #{command_name}"
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    puts "huh"
    # options = {}
    # params = {}
    # optparse = Morpheus::Cli::OptionParser.new do |opts|
    #   opts.banner = subcommand_usage()
    #   build_standard_list_options(opts, options)
    #   opts.footer = "List Oauth Clients."
    # end
    # connect(options)

    # @clients_interface.setopts(options)
    # if options[:dry_run]
    #   print_dry_run @clients_interface.dry.list(params)
    #   return 0
    # end

    # json_response = @clients_interface.list(params)
    # render_response(json_response, options, "clients") do 
    #   clients = json_response["clients"]
    #   if clients.emtpy?
    #     print cyan,"No clients found",reset,"\n"
    #   else
    #     rows = clients.collect {|client|
    #       row = {
    #         id: client['id'],
    #         client_id = client['clientId']
    #       }
    #     }
    #     columns = [:id, {:client_id => {:max_width => 50}}]
    #     print cyan
    #     print as_pretty_table(rows, columns, options)
    #     print reset
    #     print_results_pagination(json_response)
    #   end
    #   print reset,"\n"
    # end
    # return 0, nil
  end

end