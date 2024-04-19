require 'morpheus/cli/cli_command'

class Morpheus::Cli::EmailTemplates
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :update, :remove, :execute

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @email_templates_interface = @api_client.email_templates
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")

      build_standard_list_options(opts, options)
      opts.footer = "List email templates."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @email_templates_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @email_templates.dry.list(params)
      return
    end

    json_response = @email_templates_interface.list(params)
    templates = json_response['emailTemplates']
    render_response(json_response, options, 'templates') do
      title = "Morpheus Email Templates"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if templates.empty?
        print cyan,"No templates found.",reset,"\n"
      else
        print cyan
        print_templates_table(templates, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if templates.empty?
      return 1, "no templates found"
    else
      return 0, nil
    end
  end

  def print_templates_table(templates, opts={})
    columns = [
      {"ID" => lambda {|it| it['id'] } },
      {"NAME" => lambda {|it| it['name'] } },
      {"ACCOUNT" => lambda {|it| it['account']['name'] || 'System'} }

      # {"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(templates, columns, opts)
  end
end