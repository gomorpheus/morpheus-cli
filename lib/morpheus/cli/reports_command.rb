require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::ReportsCommand
  include Morpheus::Cli::CliCommand
  set_command_hidden # until complete
  set_command_name :reports

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @reports_interface = @api_client.reports
  end

  register_subcommands :list, :get, # :run, :remove
  
  # set_default_subcommand :list
  
  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @reports_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @reports_interface.dry.list(params)
        return
      end

      json_response = @reports_interface.list(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      boot_scripts = json_response['bootScripts']
      title = "Morpheus Boot Scripts"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if boot_scripts.empty?
        print cyan,"No boot scripts found.",reset,"\n"
      else
        rows = boot_scripts.collect {|boot_script| 
            row = {
              id: boot_script['id'],
              name: boot_script['fileName']
            }
            row
          }
          columns = [:id, :name]
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[boot-script]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [boot-script]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      @reports_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @reports_interface.dry.get(args[0].to_i)
        else
          print_dry_run @reports_interface.dry.list({name:args[0]})
        end
        return
      end
      boot_script = find_boot_script_by_name_or_id(args[0])
      return 1 if boot_script.nil?
      json_response = {'bootScript' => boot_script}  # skip redundant request
      # json_response = @reports_interface.get(boot_script['id'])
      boot_script = json_response['bootScript']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      print_h1 "Boot Script Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'fileName',
        # "Description" => 'description',
        # "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        # "Visibility" => lambda {|it| it['visibility'] ? it['visibility'].capitalize() : 'Private' },
      }
      print_description_list(description_cols, boot_script)

      print_h2 "Script"
      print cyan
      puts boot_script['content']
      
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

end

