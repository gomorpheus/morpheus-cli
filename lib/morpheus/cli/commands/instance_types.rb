require 'morpheus/cli/cli_command'

class Morpheus::Cli::InstanceTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  register_subcommands :list, :get
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @instance_types_interface = @api_client.instance_types
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
      opts.on('--category VALUE', String, "Filter by category") do |val|
        params['category'] = val
      end
      opts.on('--code VALUE', String, "Filter by code") do |val|
        params['code'] = val
      end
      opts.on('--technology VALUE', String, "Filter by technology") do |val|
        params['provisionTypeCode'] = val
      end
      opts.footer = "List instance types."
    end
    optparse.parse!(args)
    if args.count > 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      @instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instance_types_interface.dry.list(params)
        return
      end
      # do it
      json_response = @instance_types_interface.list(params)
      instance_types = json_response['instanceTypes']
      # print result and return output
      if options[:json]
        puts as_json(json_response, options, "instanceTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['instanceTypes'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instanceTypes")
        return 0
      end
      instance_types = json_response['instanceTypes']
      title = "Morpheus Instance Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if instance_types.empty?
        print yellow,"No instance types found.",reset,"\n"
      else
        instance_types.each do |instance_type|
          versions = instance_type['versions'].join(', ')
          print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
          if instance_type['instanceTypeLayouts']
            layout_names = instance_type['instanceTypeLayouts'].collect { |layout| layout['name'] }.uniq.sort
            layout_names.each do |layout_name|
              print green, "     - #{layout_name}\n",reset
            end
          end
        end
        if json_response['meta']
          print_results_pagination(json_response, {:label => "instance type", :n_label => "instance types"})
        end
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get instance type details." + "\n" +
                    "[name] is required. This is the name or id of an instance type."
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      instance_type = find_instance_type_by_name_or_id(args[0])
      if instance_type.nil?
        return 1
      end
      @instance_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instance_types_interface.dry.get(instance_type['id'])
        return
      end
      json_response = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        json_response = {'instanceType' => instance_type}
      else
        json_response = @instance_types_interface.get(instance_type['id'])
        instance_type = json_response['instanceType']
      end

      if options[:json]
        puts as_json(json_response, options, "instanceType")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instanceType")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['instanceType']], options)
        return 0
      end

      print_h1 "Instance Type Details"
      versions = instance_type['versions'].join(', ')
      print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
      if instance_type['instanceTypeLayouts']
        layout_names = instance_type['instanceTypeLayouts'].collect { |layout| layout['name'] }.uniq.sort
        layout_names.each do |layout_name|
          print green, "     - #{layout_name}\n",reset
        end
      else
        print yellow,"No layouts found for instance type.","\n",reset
      end
      print reset,"\n"
      

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

end
