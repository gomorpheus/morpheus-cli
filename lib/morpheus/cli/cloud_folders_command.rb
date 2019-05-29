require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::CloudFoldersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  #set_command_name :'cloud-folders'
  set_command_name :'resource-folders'

  register_subcommands :list, :get, :add, :update, :remove
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @cloud_folders_interface = @api_client.cloud_folders
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
      opts.banner = subcommand_usage("[cloud]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List resource folders for a cloud." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud."
    end
    optparse.parse!(args)
    if args.count == 1
      cloud_id = args[0]
    elsif args.count == 0 && cloud_id
      # support -c
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
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

      params.merge!(parse_list_options(options))
      @cloud_folders_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_folders_interface.dry.list(cloud['id'], params)
        return
      end
      json_response = @cloud_folders_interface.list(cloud['id'], params)
      folders = json_response["folders"]
      if options[:json]
        puts as_json(json_response, options, "folders")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "folders")
        return 0
      elsif options[:csv]
        puts records_as_csv(folders, options)
        return 0
      end
      title = "Morpheus Resource Folders - Cloud: #{cloud['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if folders.empty?
        print cyan,"No resource folders found.",reset,"\n"
      else
        rows = folders.collect {|folder| 
          formatted_name = (folder['depth'] && folder['depth'] > 0) ? (('  ' * folder['depth'].to_i) + folder['name'].to_s) : folder['name'].to_s
          row = {
            id: folder['id'],
            # name: folder['name'],
            name: formatted_name,
            type: folder['type'].to_s.capitalize,
            description: folder['description'],
            active: format_boolean(folder['active']),
            visibility: folder['visibility'].to_s.capitalize,
            default: format_boolean(folder['defaultFolder']),
            imageTarget: format_boolean(folder['defaultStore']),
            tenants: folder['tenants'] ? folder['tenants'].collect {|it| it['name'] }.uniq.join(', ') : ''
            # owner: folder['owner'] ? folder['owner']['name'] : ''
          }
          row
        }
        columns = [:id, :name, :active, :default, :visibility, :tenants]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    folder_id = nil
    cloud_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [folder]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a resource folder." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud." + "\n"
                    "[folder] is required. This is the name or id of a resource folder."
    end
    optparse.parse!(args)
    if args.count == 2
      cloud_id = args[0]
      folder_id = args[1]
    elsif args.count == 1 && cloud_id
      folder_id = args[0]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
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
      @cloud_folders_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @cloud_folders_interface.dry.get(cloud['id'], folder_id.to_i)
        else
          print_dry_run @cloud_folders_interface.dry.list(cloud['id'], {name:folder_id})
        end
        return
      end
      folder = find_folder_by_name_or_id(cloud['id'], folder_id)
      return 1 if folder.nil?
      json_response = {'folder' => folder}  # skip redundant request
      # json_response = @folders_interface.get(folder['id'])
      folder = json_response['folder']
      if options[:json]
        puts as_json(json_response, options, "folder")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "folder")
        return 0
      elsif options[:csv]
        puts records_as_csv([folder], options)
        return 0
      end
      print_h1 "Resource Folder Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        #"Type" => lambda {|it| it['type'].to_s.capitalize },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Default" => lambda {|it| format_boolean(it['defaultPool']) },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        #"Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' }
        # "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      }
      print_description_list(description_cols, folder)

      if folder['resourcePermission'].nil?
        #print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if folder['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if folder['resourcePermission']['sites']
          folder['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        group_columns = {
          "GROUP" => 'name',
          "DEFAULT" => lambda {|it| it['default'].nil? ? '' : format_boolean(it['default']) }
        }
        print cyan
        print as_pretty_table(rows, group_columns)
      end

      if folder['resourcePermission'] && folder['resourcePermission']['plans']
        print_h2 "Service Plan Access"
        rows = []
        if folder['resourcePermission']['allPlans']
          rows.push({"name" => 'All'})
        end
        if folder['resourcePermission']['plans']
          folder['resourcePermission']['plans'].each do |plan|
            rows.push(plan)
          end
        end
        # rows = rows.collect do |site|
        #   {plan: site['name'], default: site['default'] ? 'Yes' : ''}
        #   #{group: site['name']}
        # end
        plan_columns = {
          "PLAN" => 'name',
          "DEFAULT" => lambda {|it| it['default'].nil? ? '' : format_boolean(it['default']) }
        }
        print cyan
        print as_pretty_table(rows, plan_columns)
      end

      if folder['tenants'].nil? || folder['tenants'].empty?
        #print "\n", "No tenant permissions found", "\n"
      else
        print_h2 "Tenant Permissions"
        rows = []
        rows = folder['tenants'] || []
        tenant_columns = {
          "TENANT" => 'name',
          "DEFAULT" => lambda {|it| format_boolean(it['defaultTarget']) },
          "IMAGE TARGET" => lambda {|it| format_boolean(it['defaultStore']) }
        }
        print cyan
        print as_pretty_table(rows, tenant_columns)
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
    folder_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud] [folder] [options]")
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        cloud_id = val
      end
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
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
      opts.on('--active [on|off]', String, "Can be used to disable a resource folder") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a resource folder." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud." + "\n"
                    "[folder] is required. This is the id of a folder."
    end
    optparse.parse!(args)
    if args.count == 2
      cloud_id = args[0]
      folder_id = args[1]
    elsif args.count == 1 && cloud_id
      folder_id = args[0]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
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

      folder = find_folder_by_name_or_id(cloud['id'], folder_id)
      return 1 if folder.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for resource folder options
        payload = {
          'folder' => {
          }
        }
        
        # allow arbitrary -O options
        payload['folder'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      
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
          payload['folder']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['folder']['visibility'] = options['visibility']
        end

      end
      @cloud_folders_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @cloud_folders_interface.dry.update(cloud['id'], folder["id"], payload)
        return
      end
      json_response = @cloud_folders_interface.update(cloud['id'], folder["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        folder = json_response['folder']
        print_green_success "Updated resource folder #{folder['name']}"
        get([folder['id'], "-c", cloud['id'].to_s]) # argh, to_s needed on option values..
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


  def find_folder_by_name_or_id(cloud_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_folder_by_id(cloud_id, val)
    else
      return find_folder_by_name(cloud_id, val)
    end
  end

  def find_folder_by_id(cloud_id, id)
    begin
      json_response = @cloud_folders_interface.get(cloud_id, id.to_i)
      return json_response['folder']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Resource Folder not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_folder_by_name(cloud_id, name)
    json_response = @cloud_folders_interface.list(cloud_id, {name: name.to_s})
    folders = json_response['folders']
    if folders.empty?
      print_red_alert "Resource Folder not found by name #{name}"
      return nil
    elsif folders.size > 1
      matching_folders = folders.select { |it| it['name'] == name }
      if matching_folders.size == 1
        return matching_folders[0]
      end
      print_red_alert "#{folders.size} resource folders found by name #{name}"
      rows = folders.collect do |it|
        {id: it['id'], name: it['name']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      folder = folders[0]
      # merge in tenants map
      if json_response['tenants'] && json_response['tenants'][folder['id']]
        folder['tenants'] = json_response['tenants'][folder['id']]
      end
      return folder
    end
  end

end
