require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworkServicesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'network-services'

  # register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :list
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_services_interface = @api_client.network_services
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List network services."
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @network_services_interface.dry.list(params)
        return
      end
      json_response = @network_services_interface.list(params)
      network_services = json_response["networkServices"]
      if options[:include_fields]
        json_response = {"networkServices" => filter_data(network_services, options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(network_services, options)
        return 0
      end
      title = "Morpheus Network Services"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if network_services.empty?
        print cyan,"No network services found.",reset,"\n"
      else
        rows = network_services.collect {|network_service| 
          row = {
            id: network_service['id'],
            name: network_service['name'],
            type: network_service['type'] ? network_service['type']['name'] : '',
          }
          row
        }
        columns = [:id, :name, :type]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "network service", :n_label => "network services"})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
  

  private


 def find_network_service_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_service_by_id(val)
    else
      return find_network_service_by_name(val)
    end
  end

  def find_network_service_by_id(id)
    begin
      json_response = @network_services_interface.get(id.to_i)
      return json_response['networkService']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Service not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_service_by_name(name)
    json_response = @network_services_interface.list({name: name.to_s})
    network_services = json_response['networkServices']
    if network_services.empty?
      print_red_alert "Network Service not found by name #{name}"
      return nil
    elsif network_services.size > 1
      print_red_alert "#{network_services.size} network services found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_services.collect do |network_service|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      return network_services[0]
    end
  end

end
