require 'morpheus/cli/cli_command'

class Morpheus::Cli::Options
  include Morpheus::Cli::CliCommand

  set_command_description "List options by source name or option type"
  set_command_name :'options'
  
  # options is not published yet
  set_command_hidden

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @options_interface = @api_client.options
  end
  
  def handle(args)
    list(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: morpheus #{command_name} [source] [option-type]"
      # build_standard_list_options(opts, options)
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
View options by source name or list options for a specific library option type.
[source] is required. This is the name of the options source to load eg. "currencies"
[option-type] is required when [source] is 'list'. This is the name or id of an option type to view.

Examples: 
    options currencies
    options dnsRecordType
    options list "widgets"
EOT
    end
    optparse.parse!(args)
    source_name = args[0]
    option_type_id = args.size > 1 ? args[1..-1].join(" ") : nil
    if source_name == "list"
      verify_args!(args:args, optparse:optparse, min: 2)
    else
      verify_args!(args:args, optparse:optparse, count: 1)
    end
    connect(options)
    params.merge!(parse_list_options(options))
    if source_name == "list"
      if option_type_id.to_s =~ /\A\d{1,}\Z/
        params["optionTypeId"] = option_type_id
      else
        option_type = find_by_name_or_id(:option_type, option_type_id)
        if option_type.nil?
          return 1, "Option Type not found by name '#{option_type_id}'"
        end
        params["optionTypeId"] = option_type["id"]
      end
    end
    # could find_by_name_or_id for params['servers'] and params['containers']
    @options_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @options_interface.dry.options_for_source(source_name, params)
      return
    end
    json_response = nil
    begin
      json_response = @options_interface.options_for_source(source_name, params)
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        raise_command_error("Options source not found by name '#{source_name}'", args, optparse)
      elsif e.response && e.response.code == 500
        # API is actually returning 500, so just expect it
        if e.response.body.to_s.include?("groovy.lang.MissingMethodException")
          raise_command_error("Options source not found by name '#{source_name}'", args, optparse)
        else
          raise e
        end
      else
        raise e
      end
    end
    render_response(json_response, options, "data") do
      records = json_response["data"]
      # print_h1 "Morpheus Options: #{source}", parse_list_subtitles(options), options
      print_h1 "Morpheus Options", ["Source: #{source_name}"] + parse_list_subtitles(options), options
      if records.nil? || records.empty?
        print cyan,"No options found.",reset,"\n"
      else
        print as_pretty_table(records, [:name, :value], options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

end
