require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::CloudDatastoresCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  # set_command_name :'cloud-datastores'
  set_command_name :'datastores'

  register_subcommands :list, :get, :update
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @cloud_datastores_interface = @api_client.cloud_datastores
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    cloud_id = nil
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("-c [cloud]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List datastores for a cloud." + "\n" +
                    "-c [cloud] is required. This is the name or id of the cloud."
    end
    optparse.parse!(args)
    connect(options)
    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      params.merge!(parse_list_options(options))
      @cloud_datastores_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_datastores_interface.dry.list(cloud['id'], params)
        return
      end
      json_response = @cloud_datastores_interface.list(cloud['id'], params)
      datastores = json_response["datastores"]
      if options[:json]
        puts as_json(json_response, options, "datastores")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "datastores")
        return 0
      elsif options[:csv]
        puts records_as_csv(datastores, options)
        return 0
      end
      title = "Morpheus Datastores - Cloud: #{cloud['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if datastores.empty?
        print cyan,"No datastores found.",reset,"\n"
      else
        rows = datastores.collect {|datastore| 
          row = {
            id: datastore['id'],
            name: datastore['name'],
            type: datastore['type'].to_s.capitalize,
            #cloud: datastore['zone'] ? datastore['zone']['name'] : '',
            capacity: datastore['freeSpace'] ? Filesize.from("#{datastore['freeSpace']} B").pretty.strip : "Unknown",
            online: format_boolean(datastore['online']),
            active: format_boolean(datastore['active']),
            visibility: datastore['visibility'].to_s.capitalize,
            tenants: datastore['tenants'] ? datastore['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
            # owner: datastore['owner'] ? datastore['owner']['name'] : ''
          }
          row
        }
        columns = [:id, :name, :type, :capacity, :online, :active, :visibility, :tenants]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "datastore", :n_label => "datastores"})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    cloud_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[datastore]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a datastore." + "\n" +
                    "[datastore] is required. This is the name or id of a datastore." + "\n" +
                    "-c [cloud] is required. This is the name or id of the cloud."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [datastore]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?
      @cloud_datastores_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @cloud_datastores_interface.dry.get(cloud['id'], args[0].to_i)
        else
          print_dry_run @cloud_datastores_interface.dry.list(cloud['id'], {name:args[0]})
        end
        return
      end
      datastore = find_datastore_by_name_or_id(cloud['id'], args[0])
      return 1 if datastore.nil?
      json_response = {'datastore' => datastore}  # skip redundant request
      # json_response = @datastores_interface.get(datastore['id'])
      datastore = json_response['datastore']
      if options[:json]
        puts as_json(json_response, options, "datastore")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "datastore")
        return 0
      elsif options[:csv]
        puts records_as_csv([datastore], options)
        return 0
      end
      print_h1 "Datastore Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| it['type'].to_s.capitalize },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "Capacity" => lambda {|it| it['freeSpace'] ? Filesize.from("#{it['freeSpace']} B").pretty.strip : "Unknown" },
        "Online" => lambda {|it| format_boolean(it['online']) },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        # "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      }
      print_description_list(description_cols, datastore)

      if datastore['resourcePermission'].nil?
        print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if datastore['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if datastore['resourcePermission']['sites']
          datastore['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        rows = rows.collect do |site|
          # {group: site['name'], default: site['default'] ? 'Yes' : ''}
          {group: site['name']}
        end
        # columns = [:group, :default]
        columns = [:group]
        print cyan
        print as_pretty_table(rows, columns)
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    cloud_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[datastore] -c [cloud] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      # opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
      #   if list.size == 1 && list[0] == 'null' # hacky way to clear it
      #     group_defaults_list = []
      #   else
      #     group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
      #   end
      # end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a datastore") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a datastore." + "\n" +
                    "[datastore] is required. This is the id of a datstore."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      # load cloud
      if cloud_id.nil?
        puts_error "#{Morpheus::Terminal.angry_prompt}missing required option: [cloud]\n#{optparse}"
        return 1
      end
      cloud = find_cloud_by_name_or_id(cloud_id)
      return 1 if cloud.nil?

      datastore = find_datastore_by_name_or_id(cloud['id'], args[0])
      return 1 if datastore.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for datastore options
        payload = {
          'datastore' => {
          }
        }
        
        # allow arbitrary -O options
        payload['datastore'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      
        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end

        # Active
        if options['active'] != nil
          payload['datastore']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['datastore']['visibility'] = options['visibility']
        end

      end
      @cloud_datastores_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_datastores_interface.dry.update(cloud['id'], datastore["id"], payload)
        return
      end
      json_response = @cloud_datastores_interface.update(cloud['id'], datastore["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        datastore = json_response['datastore']
        print_green_success "Updated datastore #{datastore['name']}"
        get([datastore['id'], "-c", cloud['id'].to_s]) # argh, to_s needed on option values..
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


  def find_datastore_by_name_or_id(cloud_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_datastore_by_id(cloud_id, val)
    else
      return find_datastore_by_name(cloud_id, val)
    end
  end

  def find_datastore_by_id(cloud_id, id)
    begin
      json_response = @cloud_datastores_interface.get(cloud_id, id.to_i)
      return json_response['datastore']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Datastore not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_datastore_by_name(cloud_id, name)
    json_response = @cloud_datastores_interface.list(cloud_id, {name: name.to_s})
    datastores = json_response['datastores']
    if datastores.empty?
      print_red_alert "Datastore not found by name #{name}"
      return nil
    elsif datastores.size > 1
      print_red_alert "#{datastores.size} datastores found by name #{name}"
      # print_datastores_table(datastores, {color: red})
      rows = datastores.collect do |it|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      datastore = datastores[0]
      # merge in tenants map
      if json_response['tenants'] && json_response['tenants'][datastore['id']]
        datastore['tenants'] = json_response['tenants'][datastore['id']]
      end
      return datastore
    end
  end

end
