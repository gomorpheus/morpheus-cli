require 'io/console'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::InstanceTypes
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit
    end
    name = args[0]
    connect(options)
    begin
      if options[:dry_run]
        print_dry_run @instance_types_interface.dry.get({name: name})
        return
      end
      json_response = @instance_types_interface.get({name: name})

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      instance_type = json_response['instanceTypes'][0]

      if instance_type.nil?
        puts yellow,"No instance type found by name #{name}.",reset
      else
        print_h1 "Instance Type Details"
        versions = instance_type['versions'].join(', ')
        print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
        layout_names = instance_type['instanceTypeLayouts'].collect { |layout| layout['name'] }.uniq.sort
        layout_names.each do |layout_name|
          print green, "     - #{layout_name}\n",reset
        end
        # instance_type['instanceTypeLayouts'].each do |layout|
        #   print green, "     - #{layout['name']}\n",reset
        # end
        print reset,"\n"
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      if options[:dry_run]
        print_dry_run @instance_types_interface.dry.get(params)
        return
      end
      json_response = @instance_types_interface.get(params)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return 0
      end

      instance_types = json_response['instanceTypes']
      title = "Morpheus Instance Types"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if instance_types.empty?
        print yellow,"No instance types found.",reset,"\n"
      else
        instance_types.each do |instance_type|
          versions = instance_type['versions'].join(', ')
          print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
          layout_names = instance_type['instanceTypeLayouts'].collect { |layout| layout['name'] }.uniq.sort
          layout_names.each do |layout_name|
            print green, "     - #{layout_name}\n",reset
          end
          # instance_type['instanceTypeLayouts'].each do |layout|
          #   print green, "     - #{layout['name']}\n",reset
          # end
          #print JSON.pretty_generate(instance_type['instanceTypeLayouts'].first), "\n"
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end
end
