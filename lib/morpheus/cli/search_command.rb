require 'morpheus/cli/cli_command'
require 'yaml'

class Morpheus::Cli::SearchCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::DeploymentsHelper
  
  set_command_name :search
  set_command_description "Global search for finding all types of things"

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @search_interface = @api_client.search
  end

  def handle(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} #{command_name} [phrase]"
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
Global search that provides a way to find records of all types that match a phrase.
[phrase] is required. This is the phrase to search for, the name of an object usually.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, min:1)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    if options[:phrase].to_s.empty?
      raise_command_error "[phrase] is required.", args, optparse
    end
    params.merge!(parse_list_options(options))
    @search_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @search_interface.dry.list(params)
      return
    end
    json_response = @search_interface.list(params)
    search_results = json_response["hits"] || json_response["results"]
    render_response(json_response, options, "hits") do
      print_h1 "Morpheus Search", parse_list_subtitles(options), options
      if search_results.empty?
        print cyan,"No results found.",reset,"\n"
      else
        columns = {
          "Type" => lambda {|it| format_morpheus_type(it['type']) },
          "ID" => 'id',
          # "UUID" => 'uuid',
          "Name" => 'name',
          "Decription" => 'description',
          #"Score" => 'score',
          "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        }
        print as_pretty_table(search_results, columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if search_results.empty?
      return 1, "no results found"
    else
      return 0, nil
    end
  end

  protected

  def format_morpheus_type(val)
    if val == "ComputeSite"
      "Group"
    elsif val == "ComputeZone"
      "Cloud"
    elsif val == "ComputeServer"
      "Host"
    elsif val == "ComputeServerGroup"
      "Cluster"
    else
      val
    end
  end
  
end

