require 'morpheus/cli/cli_command'

class Morpheus::Cli::IntegrationsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'integrations'

  register_subcommands :list
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @integrations_interface = @api_client.integrations
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List integrations."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      params.merge!(parse_list_options(options))
      @integrations_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @integrations_interface.dry.list(params)
        return
      end
      json_response = @integrations_interface.list(params)

      render_result = render_with_format(json_response, options, 'integrations')
      return 0 if render_result

      title = "Morpheus Integrations"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      integrations = json_response['integrations']

      if integrations.empty?
        print yellow,"No integrations found.",reset,"\n"
      else
        rows = integrations.collect do |it|
          {
              id: it['id'],
              name: it['name'],
              status: format_integration_status(it),
              last_updated: format_local_dt(it['statusDate']),
              type: it['integrationType'] ? it['integrationType']['name'] : ''
          }
        end
        columns = [ :id, :name, :status, :last_updated, :type]
        print as_pretty_table(rows, columns)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def format_integration_status(integration, return_color=cyan)
    out = ""
    status_string = integration['status']
    if integration['enabled'] == false
      out << "#{red}DISABLED#{integration['statusMessage'] ? "#{return_color} - #{integration['statusMessage']}" : ''}#{return_color}"
    elsif status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{integration['statusMessage'] ? "#{return_color} - #{integration['statusMessage']}" : ''}#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'error' || status_string == 'offline'
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{integration['statusMessage'] ? "#{return_color} - #{integration['statusMessage']}" : ''}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

end
