require 'morpheus/cli/cli_command'

class Morpheus::Cli::Roles
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper
  register_subcommands :list, :get, :add, :update, :remove, 
    :'list-permissions', :'update-feature-access', :'update-global-group-access', 
    :'update-group-access', :'update-global-cloud-access', :'update-cloud-access', 
    :'update-global-instance-type-access', :'update-instance-type-access', 
    :'update-global-blueprint-access', :'update-blueprint-access', 
    :'update-global-catalog-item-type-access', :'update-catalog-item-type-access', 
    :'update-persona-access', 
    :'update-global-vdi-pool-access', :'update-vdi-pool-access',
    :'update-global-report-type-access', :'update-report-type-access'
  alias_subcommand :details, :get
  set_default_subcommand :list

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @whoami_interface = @api_client.whoami
    @account_users_interface = @api_client.account_users
    @accounts_interface = @api_client.accounts
    @roles_interface = @api_client.roles
    @groups_interface = @api_client.groups
    @options_interface = @api_client.options
    @instances_interface = @api_client.instances
    @instance_types_interface = @api_client.instance_types
    @blueprints_interface = @api_client.blueprints
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search phrase]")
      opts.on( '--tenant TENANT', "Tenant Filter for list of Roles." ) do |val|
        options[:tenant] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List roles."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    options[:phrase] = args.join(" ") if args.count > 0
    connect(options)

    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil
    params = {}
    params.merge!(parse_list_options(options))
    @roles_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @roles_interface.dry.list(account_id, params), options
      return 0, nil
    end
    load_whoami()
    if options[:tenant]
      params[:tenant] = options[:tenant]
    end
    json_response = @roles_interface.list(account_id, params)

    render_response(json_response, options, "roles") do
      roles = json_response['roles']
      title = "Morpheus Roles"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if roles.empty?
        print cyan,"No roles found.",reset,"\n"
      else
        print cyan
        columns = @is_master_account ? role_column_definitions : subtenant_role_column_definitions
        print as_pretty_table(roles, columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      opts.on('-p','--permissions', "Display Permissions") do |val|
        options[:include_feature_access] = true
      end
      opts.on('-f','--feature-access', "Display Permissions [deprecated]") do |val|
        options[:include_feature_access] = true
      end
      opts.add_hidden_option('--feature-access')
      opts.on('-g','--group-access', "Display Group Access") do
        options[:include_group_access] = true
      end
      opts.on('-c','--cloud-access', "Display Cloud Access") do
        options[:include_cloud_access] = true
      end
      opts.on('-i','--instance-type-access', "Display Instance Type Access") do
        options[:include_instance_type_access] = true
      end
      opts.on('-b','--blueprint-access', "Display Blueprint Access") do
        options[:include_blueprint_access] = true
      end
      opts.on(nil,'--catalog-item-type-access', "Display Catalog Item Type Access") do
        options[:include_catalog_item_type_access] = true
      end
      opts.on(nil,'--personas', "Display Persona Access") do
        options[:include_personas_access] = true
      end
      opts.on(nil,'--vdi-pool-access', "Display VDI Pool Access") do
        options[:include_vdi_pool_access] = true
      end
      opts.on(nil,'--report-type-access', "Display Report Type Access") do
        options[:include_report_type_access] = true
      end
      opts.on('-a','--all', "Display All Access Lists") do
        options[:include_feature_access] = true
        options[:include_group_access] = true
        options[:include_cloud_access] = true
        options[:include_instance_type_access] = true
        options[:include_blueprint_access] = true
        options[:include_catalog_item_type_access] = true
        options[:include_personas_access] = true
        options[:include_vdi_pool_access] = true
        options[:include_report_type_access] = true
      end
      opts.on('--account-id ID', String, "Clarify Owner of Role") do |val|
        if has_complete_access
          options[:account_id] = val.to_s
        end
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a role.
[role] is required. This is the name (authority) or id of a role.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options={})
    args = [id] # heh
    params = {}

    
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      params.merge!(parse_query_options(options))

      @roles_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @roles_interface.dry.get(account_id, args[0].to_i)
        else
          print_dry_run @roles_interface.dry.list(account_id, {name: args[0]})
        end
        return
      end

      # role = find_role_by_name_or_id(account_id, args[0])
      # exit 1 if role.nil?
      # refetch from show action, argh
      # json_response = @roles_interface.get(account_id, role['id'])
      # role = json_response['role']
      load_whoami()
      json_response = nil
      role = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        json_response = @roles_interface.get(account_id, args[0].to_i)
        role = json_response['role']
      else
        role = find_role_by_name_or_id(account_id, args[0])
        exit 1 if role.nil?
        # refetch from show action, argh
        json_response = @roles_interface.get(account_id, role['id'])
        role = json_response['role']
      end

      render_response(json_response, options, 'role') do
      
      print cyan
      print_h1 "Role Details", options
      print cyan
      columns = @is_master_account ? role_column_definitions : subtenant_role_column_definitions
      print_description_list(columns, role, options)

      # print_h2 "Role Instance Limits", options
      # print cyan
      # print_description_list({
      #   "Max Storage"  => lambda {|it| (it && it['maxStorage'].to_i != 0) ? Filesize.from("#{it['maxStorage']} B").pretty : "no limit" },
      #   "Max Memory"  => lambda {|it| (it && it['maxMemory'].to_i != 0) ? Filesize.from("#{it['maxMemory']} B").pretty : "no limit" },
      #   "CPU Count"  => lambda {|it| (it && it['maxCpu'].to_i != 0) ? it['maxCpu'] : "no limit" }
      # }, role['instanceLimits'])

      print_h2 "Permissions", options
      print cyan
      if options[:include_feature_access]
        rows = json_response['featurePermissions'].collect do |it|
          {
            code: it['code'],
            name: it['name'],
            subCategory: it['subCategory'],
            access: format_access_string(it['access']),
          }
        end
        if options[:sort]
          rows.sort! {|a,b| a[options[:sort]] <=> b[options[:sort]] }
        end
        if options[:direction] == 'desc'
          rows.reverse!
        end
        if options[:phrase]
          phrase_regexp = /#{Regexp.escape(options[:phrase])}/i
          rows = rows.select {|row| row[:code].to_s =~ phrase_regexp || row[:name].to_s =~ phrase_regexp }
        end
        print as_pretty_table(rows, [:code, :name, :subCategory, :access], options)
        # print reset,"\n"
      else
        print cyan,"Use --permissions to list feature permissions","\n"
      end

      has_group_access = true
      has_cloud_access = true
      print_h2 "Global Access", options
      global_access_columns = {
        "Groups" => lambda {|it| get_access_string(it['globalSiteAccess']) },
        "Clouds" => lambda {|it| get_access_string(it['globalZoneAccess']) },
        "Instance Types" => lambda {|it| get_access_string(it['globalInstanceTypeAccess']) },
        "Blueprints" => lambda {|it| get_access_string(it['globalAppTemplateAccess'] || it['globalBlueprintAccess']) },
        "Catalog Item Types" => lambda {|it| get_access_string(it['globalCatalogItemTypeAccess']) },
        "VDI Pools" => lambda {|it| get_access_string(it['globalVdiPoolAccess']) },
        "Report Types" => lambda {|it| get_access_string(it['globalReportTypeAccess']) },
      }
      if role['roleType'].to_s.downcase == 'account'
        global_access_columns.delete("Groups")
        has_group_access = false
      else
        global_access_columns.delete("Clouds")
        has_cloud_access = false
      end
      print as_pretty_table([json_response], global_access_columns, options)

      if has_group_access
        #print_h2 "Group Access: #{get_access_string(json_response['globalSiteAccess'])}", options
        print cyan
        if json_response['globalSiteAccess'] == 'custom'
          print_h2 "Group Access", options
          if options[:include_group_access]
            rows = json_response['sites'].collect do |it|
              {
                name: it['name'],
                access: format_access_string(it['access'], ["none","read","full"]),
              }
            end
            print as_pretty_table(rows, [:name, :access], options)
          else
            print cyan,"Use -g, --group-access to list custom access","\n"
          end
          # print reset,"\n"
        else
          # print "\n"
          # print cyan,bold,"Group Access: #{get_access_string(json_response['globalSiteAccess'])}",reset,"\n"
        end
      end
      
      if has_cloud_access
        print cyan
        #puts "Cloud Access: #{get_access_string(json_response['globalZoneAccess'])}"
        #print "\n"
        if json_response['globalZoneAccess'] == 'custom'
          print_h2 "Cloud Access", options
          if options[:include_cloud_access]
            rows = json_response['zones'].collect do |it|
              {
                name: it['name'],
                access: format_access_string(it['access'], ["none","read","full"]),
              }
            end
            print as_pretty_table(rows, [:name, :access], options)
          else
            print cyan,"Use -c, --cloud-access to list custom access","\n"
          end
          # print reset,"\n"
        else
          # print "\n"
          # print cyan,bold,"Cloud Access: #{get_access_string(json_response['globalZoneAccess'])}",reset,"\n"
        end
      end

      print cyan
      # puts "Instance Type Access: #{get_access_string(json_response['globalInstanceTypeAccess'])}"
      # print "\n"
      instance_type_global_access = json_response['globalInstanceTypeAccess']
      instance_type_permissions = role['instanceTypes'] ? role['instanceTypes'] : (json_response['instanceTypePermissions'] || [])
      if instance_type_global_access == 'custom'
        print_h2 "Instance Type Access", options
        if options[:include_instance_type_access]
          rows = instance_type_permissions.collect do |it|
            {
              name: it['name'],
              access: format_access_string(it['access'], ["none","read","full"]),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use -i, --instance-type-access to list custom access","\n"
        end
        # print reset,"\n"
      else
        # print "\n"
        # print cyan,bold,"Instance Type Access: #{get_access_string(json_response['globalInstanceTypeAccess'])}",reset,"\n"
      end

      blueprint_global_access = json_response['globalAppTemplateAccess'] || json_response['globalBlueprintAccess']
      blueprint_permissions = (role['appTemplates'] || role['blueprints']) ? (role['appTemplates'] || role['blueprints']) : (json_response['appTemplatePermissions'] || json_response['blueprintPermissions'] || [])
      print cyan
      # print_h2 "Blueprint Access: #{get_access_string(json_response['globalAppTemplateAccess'])}", options
      # print "\n"
      if blueprint_global_access == 'custom'
        print_h2 "Blueprint Access", options
        if options[:include_blueprint_access]
          rows = blueprint_permissions.collect do |it|
            {
              name: it['name'],
              access: format_access_string(it['access'], ["none","read","full"]),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use -b, --blueprint-access to list custom access","\n"
        end
        # print reset,"\n"
      else
        # print "\n"
        # print cyan,bold,"Blueprint Access: #{get_access_string(json_response['globalAppTemplateAccess'])}",reset,"\n"
      end
      
      catalog_item_type_global_access = json_response['globalCatalogItemTypeAccess']
      catalog_item_type_permissions = role['catalogItemTypes'] ? role['catalogItemTypes'] : (json_response['catalogItemTypePermissions'] || [])
      print cyan
      # print_h2 "catalog_item_type Access: #{get_access_string(json_response['globalCatalogItemTypeAccess'])}", options
      # print "\n"
      if catalog_item_type_global_access == 'custom'
        print_h2 "Catalog Item Type Access", options
        if options[:include_catalog_item_type_access]
          rows = catalog_item_type_permissions.collect do |it|
            {
              name: it['name'],
              access: format_access_string(it['access'], ["none","read","full"]),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use --catalog-item-type-access to list custom access","\n"
        end
      else
        # print "\n"
        # print cyan,bold,"Catalog Item Type Access: #{get_access_string(json_response['globalCatalogItemTypeAccess'])}",reset,"\n"
      end
      
      persona_permissions = role['personas'] ? role['personas'] : (json_response['personaPermissions'] || [])
      # if options[:include_personas_access]
      print cyan
      if persona_permissions
        print_h2 "Persona Access", options
        rows = persona_permissions.collect do |it|
          {
            name: it['name'],
            access: format_access_string(it['access'], ["none","read","full"]),
          }
        end
        print as_pretty_table(rows, [:name, :access], options)        
      end

      # print reset,"\n"
      
      vdi_pool_global_access = json_response['globalVdiPoolAccess']
      vdi_pool_permissions = role['vdiPools'] ? role['vdiPools'] : (json_response['vdiPoolPermissions'] || [])
      print cyan
      if vdi_pool_global_access == 'custom'
        print_h2 "VDI Pool Access", options
        if options[:include_vdi_pool_access]
          rows = vdi_pool_permissions.collect do |it|
            {
              name: it['name'],
              access: format_access_string(it['access'], ["none","full"]),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use --vdi-pool-access to list custom access","\n"
        end
      else
        # print "\n"
        # print cyan,bold,"VDI Pool Access: #{get_access_string(json_response['globalVdiPoolAccess'])}",reset,"\n"
      end

      report_type_global_access = json_response['globalReportTypeAccess']
      report_type_permissions = role['reportTypes'] ? role['reportTypes'] : (json_response['reportTypePermissions'] || [])
      print cyan
      if report_type_global_access == 'custom'
        print_h2 "Report Type Access", options
        if options[:include_report_type_access]
          rows = report_type_permissions.collect do |it|
            {
              name: it['name'],
              access: format_access_string(it['access'], ["none","full"]),
            }
          end
          print as_pretty_table(rows, [:name, :access], options)
        else
          print cyan,"Use --report-type-access to list custom access","\n"
        end
      else
        # print "\n"
        # print cyan,bold,"Report Type Access: #{get_access_string(json_response['globalReportTypeAccess'])}",reset,"\n"
      end

    end
    print reset,"\n"

    return 0, nil
  end

  def list_permissions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List the permissions for a role.\n" +
                    "[role] is required. This is the name or id of a role."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      # role = find_role_by_name_or_id(account_id, args[0])
      # exit 1 if role.nil?

      @roles_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @roles_interface.dry.get(account_id, args[0].to_i)
        else
          print_dry_run @roles_interface.dry.list(account_id, {name: args[0]})
        end
        return
      end

      json_response = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        json_response = @roles_interface.get(account_id, args[0].to_i)
        role = json_response['role']
      else
        role = find_role_by_name_or_id(account_id, args[0])
        exit 1 if role.nil?
        # refetch from show action, argh
        json_response = @roles_interface.get(account_id, role['id'])
        role = json_response['role']
      end

      role_permissions = json_response['featurePermissions']

      if options[:json]
        puts as_json(role_permissions, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(role_permissions, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(role_permissions)
        return 0
      end

      print cyan
      print_h1 "Role Permissions: [#{role['id']},#{role['owner']['name']}] #{role['authority']}", options

      print cyan
      if role_permissions && role_permissions.size > 0
        rows = role_permissions.collect do |it|
          {
            code: it['code'],
            name: it['name'],
            access: format_access_string(it['access']),
          }
        end
        if options[:sort]
          rows.sort! {|a,b| a[options[:sort]] <=> b[options[:sort]] }
        end
        if options[:direction] == 'desc'
          rows.reverse!
        end
        if options[:phrase]
          phrase_regexp = /#{Regexp.escape(options[:phrase])}/i
          rows = rows.select {|row| row[:code].to_s =~ phrase_regexp || row[:name].to_s =~ phrase_regexp }
        end
        print as_pretty_table(rows, [:code, :name, :access], options)
      else
        puts "No permissions found"
      end

      print reset,"\n"
      return 0
    
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_role_option_types)
      opts.on('--permissions CODE=ACCESS', String, "Set feature permission access by permission code. Example: dashboard=read,operations-wiki=full" ) do |val|
        options[:permissions] ||= {}
        parse_access_csv(options[:permissions], val, args, optparse)
      end
      opts.on('--global-group-access ACCESS', String, "Update the global group (site) access: [none|read|custom|full]" ) do |val|
        params['globalSiteAccess'] = val.to_s.downcase
      end
      opts.on('--groups ID=ACCESS', String, "Set group (site) to a custom access by group id. Example: 1=none,2=full,3=read" ) do |val|
        options[:group_permissions] ||= {}
        parse_access_csv(options[:group_permissions], val, args, optparse)
      end
      opts.on('--global-cloud-access ACCESS', String, "Update the global cloud (zone) access: [none|custom|full]" ) do  |val|
        params['globalZoneAccess'] = val.to_s.downcase
      end
      opts.on('--clouds ID=ACCESS', String, "Set cloud (zone) to a custom access by cloud id. Example: 1=none,2=full,3=read" ) do |val|
        options[:cloud_permissions] ||= {}
        parse_access_csv(options[:cloud_permissions], val, args, optparse)
      end
      opts.on('--global-instance-type-access ACCESS', String, "Update the global instance type access: [none|custom|full]" ) do  |val|
        params['globalInstanceTypeAccess'] = val.to_s.downcase
      end
      opts.on('--instance-types CODE=ACCESS', String, "Set instance type to a custom access instance type code. Example: nginx=full,apache=none" ) do |val|
        options[:instance_type_permissions] ||= {}
        parse_access_csv(options[:instance_type_permissions], val, args, optparse)
      end
      opts.on('--global-blueprint-access ACCESS', String, "Update the global blueprint access: [none|custom|full]" ) do  |val|
        params['globalAppTemplateAccess'] = val.to_s.downcase
      end
      opts.on('--blueprints ID=ACCESS', String, "Set blueprint to a custom access by blueprint id. Example: 1=full,2=none" ) do |val|
        options[:blueprint_permissions] ||= {}
        parse_access_csv(options[:blueprint_permissions], val, args, optparse)
      end
      opts.on('--global-catalog-item-type-access ACCESS', String, "Update the global catalog item type access: [none|custom|full]" ) do  |val|
        params['globalCatalogItemTypeAccess'] = val.to_s.downcase
      end
      opts.on('--catalog-item-types CODE=ACCESS', String, "Set catalog item type to a custom access by catalog item type id. Example: 1=full,2=none" ) do |val|
        options[:catalog_item_type_permissions] ||= {}
        parse_access_csv(options[:catalog_item_type_permissions], val, args, optparse)
      end
      opts.on('--personas CODE=ACCESS', String, "Set persona to a custom access by persona code. Example: standard=full,serviceCatalog=full,vdi=full" ) do |val|
        options[:persona_permissions] ||= {}
        parse_access_csv(options[:persona_permissions], val, args, optparse)
      end
      opts.on('--global-vdi-pool-access-access ACCESS', String, "Update the global VDI pool access: [none|custom|full]" ) do  |val|
        params['globalVdiPoolAccess'] = val.to_s.downcase
      end
      opts.on('--vdi-pools ID=ACCESS', String, "Set VDI pool to a custom access by VDI pool id. Example: 1=full,2=none" ) do |val|
        options[:vdi_pool_permissions] ||= {}
        parse_access_csv(options[:vdi_pool_permissions], val, args, optparse)
      end
      opts.on('--global-report-type-access ACCESS', String, "Update the global report type access: [none|custom|full]" ) do  |val|
        params['globalReportTypeAccess'] = val.to_s.downcase
      end
      opts.on('--report-types CODE=ACCESS', String, "Set report type to a custom access by report type code. Example: appCost=none,guidance=full" ) do |val|
        options[:report_type_permissions] ||= {}
        parse_access_csv(options[:report_type_permissions], val, args, optparse)
      end
      opts.on('--reset-permissions', "Reset all feature permission access to none. This can be used in conjunction with --permissions to recreate the feature permission access for the role." ) do
        options[:reset_permissions] = true
      end
      opts.on('--reset-all-access', "Reset all access to none including permissions, global groups, instance types, etc. This can be used in conjunction with --permissions to recreate the feature permission access for the role." ) do
        options[:reset_all_access] = true
      end
      opts.on('--owner ID', String, "Set the owner/tenant/account for the role by account id. Only master tenants with full permission for Tenant and Role may use this option." ) do |val|
        params['owner'] = val
      end
            opts.footer = <<-EOT
Create a new role.
[name] is required. This is a unique name (authority) for the new role.
All the role permissions and access values can be configured.
Use --permissions "CODE=ACCESS,CODE=ACCESS" to update access levels for specific feature permissions identified by code. 
Use --global-instance-type-access custom --instance-types "CODE=ACCESS,CODE=ACCESS" to customize instance type access.
Only the specified permissions,instance types, etc. are updated.
Use --reset-permissions to set access to "none" for all unspecified feature permissions.
Use --reset-all-access to set access to "none" for all unspecified feature permissions and global access values for groups, instance types, etc.
EOT
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    if args[0]
      options[:options]['authority'] = args[0]
    end
    connect(options)
    begin

      load_whoami()
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'role' => passed_options}) unless passed_options.empty?
      else
        # merge -O options into normally parsed options
        params.deep_merge!(passed_options)

        # argh, some options depend on others here...eg. multitenant is only available when roleType == 'user'
        #prompt_option_types = update_role_option_types()

        role_payload = params
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1}], options[:options])
        role_payload['authority'] = v_prompt['authority']
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'displayOrder' => 2}], options[:options])
        role_payload['description'] = v_prompt['description']

        if params['owner']
          if @is_master_account && has_complete_access
            role_payload['owner'] = params['owner']
          else
            print_red_alert "You do not have the necessary authority to use owner option"
            return
          end
        elsif @is_master_account && has_complete_access
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'owner', 'fieldLabel' => 'Owner', 'type' => 'select', 'selectOptions' => role_owner_options, 'defaultValue' => current_account['id'], 'displayOrder' => 3}], options[:options])
          role_payload['owner'] = v_prompt['owner']
        else
          role_payload['owner'] = current_account['id']
        end  

        if @is_master_account && role_payload['owner'] == current_account['id']
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleType', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => role_type_options, 'defaultValue' => 'user', 'displayOrder' => 4}], options[:options])
          role_payload['roleType'] = v_prompt['roleType']
        else
          role_payload['roleType'] = 'user'
        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'select', 'selectOptions' => base_role_options(role_payload), 'displayOrder' => 5}], options[:options])
        if v_prompt['baseRole'].to_s != ''
          base_role = find_role_by_name_or_id(account_id, v_prompt['baseRole'])
          exit 1 if base_role.nil?
          role_payload['baseRoleId'] = base_role['id']
        end

        if @is_master_account && role_payload['owner'] == current_account['id']
          if role_payload['roleType'] == 'user'
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use', 'displayOrder' => 5}], options[:options])
            role_payload['multitenant'] = ['on','true'].include?(v_prompt['multitenant'].to_s)
            if role_payload['multitenant']
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it.'}], options[:options])
              role_payload['multitenantLocked'] = ['on','true'].include?(v_prompt['multitenantLocked'].to_s)
            end
          end
        end

        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'optionSource' => 'personas', 'description' => 'Default Persona'}], options[:options], @api_client)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'selectOptions' => get_persona_select_options(), 'description' => 'Default Persona'}], options[:options], @api_client)
        role_payload['defaultPersona'] = {'code' => v_prompt['defaultPersona']} unless v_prompt['defaultPersona'].to_s.strip.empty?

        # bulk permissions
        if options[:permissions]
          perms_array = []
          options[:permissions].each do |k,v|
            perm_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => perm_code, "access" => access_value}
          end
          params['permissions'] = perms_array
        end
        if options[:group_permissions]
          perms_array = []
          options[:group_permissions].each do |k,v|
            site_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if site_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => site_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => site_id, "access" => access_value}
            end
          end
          params['sites'] = perms_array
        end
        if options[:cloud_permissions]
          perms_array = []
          options[:cloud_permissions].each do |k,v|
            zone_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if zone_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => zone_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => zone_id, "access" => access_value}
            end
            perms_array << {"id" => zone_id, "access" => access_value}
          end
          params['zones'] = perms_array
        end
        if options[:instance_type_permissions]
          perms_array = []
          options[:instance_type_permissions].each do |k,v|
            instance_type_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => instance_type_code, "access" => access_value}
          end
          params['instanceTypes'] = perms_array
        end
        if options[:blueprint_permissions]
          perms_array = []
          options[:blueprint_permissions].each do |k,v|
            blueprint_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if blueprint_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => blueprint_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => blueprint_id, "access" => access_value}
            end
          end
          params['appTemplates'] = perms_array
        end
        if options[:catalog_item_type_permissions]
          perms_array = []
          options[:catalog_item_type_permissions].each do |k,v|
            catalog_item_type_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if catalog_item_type_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => catalog_item_type_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => catalog_item_type_id, "access" => access_value}
            end
          end
          params['catalogItemTypes'] = perms_array

        end
        if options[:persona_permissions]
          perms_array = []
          options[:persona_permissions].each do |k,v|
            persona_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => persona_code, "access" => access_value}
          end
          params['personas'] = perms_array
        end
        if options[:vdi_pool_permissions]
          perms_array = []
          options[:vdi_pool_permissions].each do |k,v|
            vdi_pool_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if vdi_pool_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => vdi_pool_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => vdi_pool_id, "access" => access_value}
            end
          end
          params['vdiPools'] = perms_array
        end
        if options[:report_type_permissions]
          perms_array = []
          options[:report_type_permissions].each do |k,v|
            report_type_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => report_type_code, "access" => access_value}
          end
          params['reportTypes'] = perms_array
        end
        if options[:reset_permissions]
          params["resetPermissions"] = true
        end
        if options[:reset_all_access]
          params["resetAllAccess"] = true
        end
        payload = {"role" => role_payload}
      end
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.create(account_id, payload)
        return
      end
      json_response = @roles_interface.create(account_id, payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end

      role = json_response['role']
      display_name = role['authority'] rescue ''
      if account
        print_green_success "Added role #{display_name} to account #{account['name']}"
      else
        print_green_success "Added role #{display_name}"
      end

      get_args = [role['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
      if account
        get_args.push "--account-id", account['id'].to_s
      end

      details_options = [role_payload["authority"]]
      if account
        details_options.push "--account-id", account['id'].to_s
      end

      if role_payload['owner']
        details_options.push "--account-id", role_payload['owner'].to_s
      end
      get(details_options)

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [options]")
      build_option_type_options(opts, options, update_role_option_types)
      opts.on('--permissions CODE=ACCESS', String, "Set feature permission access by permission code. Example: dashboard=read,operations-wiki=full" ) do |val|
        options[:permissions] ||= {}
        parse_access_csv(options[:permissions], val, args, optparse)
      end
      opts.on('--global-group-access ACCESS', String, "Update the global group (site) access: [none|read|custom|full]" ) do |val|
        params['globalSiteAccess'] = val.to_s.downcase
      end
      opts.on('--groups ID=ACCESS', String, "Set group (site) to a custom access by group id. Example: 1=none,2=full,3=read" ) do |val|
        options[:group_permissions] ||= {}
        parse_access_csv(options[:group_permissions], val, args, optparse)
      end
      opts.on('--global-cloud-access ACCESS', String, "Update the global cloud (zone) access: [none|custom|full]" ) do  |val|
        params['globalZoneAccess'] = val.to_s.downcase
      end
      opts.on('--clouds ID=ACCESS', String, "Set cloud (zone) to a custom access by cloud id. Example: 1=none,2=full,3=read" ) do |val|
        options[:cloud_permissions] ||= {}
        parse_access_csv(options[:cloud_permissions], val, args, optparse)
      end
      opts.on('--global-instance-type-access ACCESS', String, "Update the global instance type access: [none|custom|full]" ) do  |val|
        params['globalInstanceTypeAccess'] = val.to_s.downcase
      end
      opts.on('--instance-types CODE=ACCESS', String, "Set instance type to a custom access instance type code. Example: nginx=full,apache=none" ) do |val|
        options[:instance_type_permissions] ||= {}
        parse_access_csv(options[:instance_type_permissions], val, args, optparse)
      end
      opts.on('--global-blueprint-access ACCESS', String, "Update the global blueprint access: [none|custom|full]" ) do  |val|
        params['globalAppTemplateAccess'] = val.to_s.downcase
      end
      opts.on('--blueprints ID=ACCESS', String, "Set blueprint to a custom access by blueprint id. Example: 1=full,2=none" ) do |val|
        options[:blueprint_permissions] ||= {}
        parse_access_csv(options[:blueprint_permissions], val, args, optparse)
      end
      opts.on('--global-catalog-item-type-access ACCESS', String, "Update the global catalog item type access: [none|custom|full]" ) do  |val|
        params['globalCatalogItemTypeAccess'] = val.to_s.downcase
      end
      opts.on('--catalog-item-types CODE=ACCESS', String, "Set catalog item type to a custom access by catalog item type id. Example: 1=full,2=none" ) do |val|
        options[:catalog_item_type_permissions] ||= {}
        parse_access_csv(options[:catalog_item_type_permissions], val, args, optparse)
      end
      opts.on('--personas CODE=ACCESS', String, "Set persona to a custom access by persona code. Example: standard=full,serviceCatalog=full,vdi=full" ) do |val|
        options[:persona_permissions] ||= {}
        parse_access_csv(options[:persona_permissions], val, args, optparse)
      end
      opts.on('--global-vdi-pool-access-access ACCESS', String, "Update the global VDI pool access: [none|custom|full]" ) do  |val|
        params['globalVdiPoolAccess'] = val.to_s.downcase
      end
      opts.on('--vdi-pools ID=ACCESS', String, "Set VDI pool to a custom access by VDI pool id. Example: 1=full,2=none" ) do |val|
        options[:vdi_pool_permissions] ||= {}
        parse_access_csv(options[:vdi_pool_permissions], val, args, optparse)
      end
      opts.on('--global-report-type-access ACCESS', String, "Update the global report type access: [none|custom|full]" ) do  |val|
        params['globalReportTypeAccess'] = val.to_s.downcase
      end
      opts.on('--report-types CODE=ACCESS', String, "Set report type to a custom access by report type code. Example: appCost=none,guidance=full" ) do |val|
        options[:report_type_permissions] ||= {}
        parse_access_csv(options[:report_type_permissions], val, args, optparse)
      end
      opts.on('--reset-permissions', "Reset all feature permission access to none. This can be used in conjunction with --permissions to recreate the feature permission access for the role." ) do
        options[:reset_permissions] = true
      end
      opts.on('--reset-all-access', "Reset all access to none including permissions, global groups, instance types, etc. This can be used in conjunction with --permissions to recreate the feature permission access for the role." ) do
        options[:reset_all_access] = true
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a role.
[role] is required. This is the name (authority) or id of a role.
All the role permissions and access values can be configured.
Use --permissions "CODE=ACCESS,CODE=ACCESS" to update access levels for specific feature permissions identified by code. 
Use --global-instance-type-access custom --instance-types "CODE=ACCESS,CODE=ACCESS" to customize instance type access.
Only the specified permissions,instance types, etc. are updated.
Use --reset-permissions to set access to "none" for all unspecified feature permissions.
Use --reset-all-access to set access to "none" for all unspecified feature permissions and global access values for groups, instance types, etc.
EOT
    end
    optparse.parse!(args)

    verify_args!(args:args, optparse:optparse, count:1)
    
    name = args[0]
    connect(options)
    begin

      load_whoami()

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'role' => passed_options}) unless passed_options.empty?
      else
        # merge -O options into normally parsed options
        params.deep_merge!(passed_options)
        prompt_option_types = update_role_option_types()
        if !@is_master_account
          prompt_option_types = prompt_option_types.reject {|it| ['roleType', 'multitenant','multitenantLocked'].include?(it['fieldName']) }
        end
        if role['roleType'] != 'user'
          prompt_option_types = prompt_option_types.reject {|it| ['multitenant','multitenantLocked'].include?(it['fieldName']) }
        end
        #params = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, options[:options], @api_client, options[:params])

        # bulk permissions
        if options[:permissions]
          perms_array = []
          options[:permissions].each do |k,v|
            perm_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => perm_code, "access" => access_value}
          end
          params['permissions'] = perms_array
        end
        if options[:group_permissions]
          perms_array = []
          options[:group_permissions].each do |k,v|
            site_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if site_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => site_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => site_id, "access" => access_value}
            end
          end
          params['sites'] = perms_array
        end
        if options[:cloud_permissions]
          perms_array = []
          options[:cloud_permissions].each do |k,v|
            zone_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if zone_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => zone_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => zone_id, "access" => access_value}
            end
            perms_array << {"id" => zone_id, "access" => access_value}
          end
          params['zones'] = perms_array
        end
        if options[:instance_type_permissions]
          perms_array = []
          options[:instance_type_permissions].each do |k,v|
            instance_type_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => instance_type_code, "access" => access_value}
          end
          params['instanceTypes'] = perms_array
        end
        if options[:blueprint_permissions]
          perms_array = []
          options[:blueprint_permissions].each do |k,v|
            blueprint_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if blueprint_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => blueprint_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => blueprint_id, "access" => access_value}
            end
          end
          params['appTemplates'] = perms_array
        end
        if options[:catalog_item_type_permissions]
          perms_array = []
          options[:catalog_item_type_permissions].each do |k,v|
            catalog_item_type_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if catalog_item_type_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => catalog_item_type_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => catalog_item_type_id, "access" => access_value}
            end
          end
          params['catalogItemTypes'] = perms_array

        end
        if options[:persona_permissions]
          perms_array = []
          options[:persona_permissions].each do |k,v|
            persona_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => persona_code, "access" => access_value}
          end
          params['personas'] = perms_array
        end
        if options[:vdi_pool_permissions]
          perms_array = []
          options[:vdi_pool_permissions].each do |k,v|
            vdi_pool_id = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            if vdi_pool_id =~ /\A\d{1,}\Z/
              perms_array << {"id" => vdi_pool_id.to_i, "access" => access_value}
            else
              perms_array << {"name" => vdi_pool_id, "access" => access_value}
            end
          end
          params['vdiPools'] = perms_array
        end
        if options[:report_type_permissions]
          perms_array = []
          options[:report_type_permissions].each do |k,v|
            report_type_code = k
            access_value = v.to_s.empty? ? "none" : v.to_s
            perms_array << {"code" => report_type_code, "access" => access_value}
          end
          params['reportTypes'] = perms_array
        end
        if options[:reset_permissions]
          params["resetPermissions"] = true
        end
        if options[:reset_all_access]
          params["resetAllAccess"] = true
        end
        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
        payload = {"role" => params}
      end
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update(account_id, role['id'], payload)
        return
      end
      json_response = @roles_interface.update(account_id, role['id'], payload)
      render_response(json_response, options, "role") do
        role = json_response['role']
        display_name = role['authority'] rescue ''
        print_green_success "Updated role #{display_name}"

        get_args = [role['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
        if account
          get_args.push "--account-id", account['id'].to_s
        end
        get(get_args)
      end
      return 0, nil

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = <<-EOT
Delete a role.
[role] is required. This is the name (authority) or id of a role.
EOT
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    name = args[0]
    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the role #{role['authority']}?")
        exit
      end
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.destroy(account_id, role['id'])
        return
      end
      json_response = @roles_interface.destroy(account_id, role['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} removed"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_feature_access(args)
    options = {}
    allowed_access_values = ['full', 'user', 'read', 'none'] # just for display , veries per permission
    permission_code = nil
    access_value = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [permission] [access]")
      opts.on( '-p', '--permission CODE', "Permission code or name" ) do |val|
        permission_code = val
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}] (varies per permission)" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update role access for a permission.
[role] is required. This is the name (authority) or id of a role.
[permission] is required. This is the code or name of a permission.
[access] is required. This is the new access value: #{ored_list(allowed_access_values)}
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:3)
    name = args[0]
    permission_code = args[1] if args[1]
    access_value = args[2].to_s.downcase if args[2]

    if !permission_code
      raise_command_error("missing required argument: [permission]", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    # access_value = access_value.to_s.downcase
    # if !allowed_access_values.include?(access_value)
    #   raise_command_error("invalid access value: #{access_value}", args, optparse)
    # end
    # need to load the permission and then split accessTypes, so just allows all for now, server validates...
    # if !['full_decrypted','full', 'read', 'custom', 'none'].include?(access_value)
    #   puts optparse
    #   exit 1
    # end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: permission_code, access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} permission #{permission_code} set to #{access_value}"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_group_access(args)
    usage = "Usage: morpheus roles update-global-group-access [role] [full|read|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [full|read|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update global group access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, read, custom or none.
Only applicable to User roles.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'read', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'ComputeSite', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global group access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_group_access(args)
    options = {}
    name = nil
    group_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'read', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [group] [access]")
      opts.on( '-g', '--group GROUP', "Group name or id" ) do |val|
        group_id = val
      end
      opts.on( nil, '--all', "Update all groups at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update role access for a group or all groups.
[role] is required. This is the name or id of a role.
--group or --all is required. This is the name or id of a group.
--access is required. This is the new access value: #{ored_list(allowed_access_values)}
Only applicable to User roles and when global group access is set to "custom".
EOT
      
    end
    optparse.parse!(args)

    # usage: update-group-access [role] [access] --all
    #        update-group-access [role] [group] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      group_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !group_id && !do_all
      raise_command_error("missing required argument: [group] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      if role_json['globalSiteAccess'] != 'custom'
        print "\n", red, "Global Group Access is currently: #{role_json['globalSiteAccess'].capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-group-access \"#{name}\" custom`"
        print "\n\n", reset
        exit 1
      end

      group = nil
      if !do_all
        group = find_group_by_name_or_id_for_provisioning(group_id)
        return 1 if group.nil?
        group_id = group['id']
      end

      params = {}
      if do_all
        params['allGroups'] = true
      else
        params['groupId'] = group_id
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_group(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_group(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all groups"
        else
          print_green_success "Role #{role['authority']} access updated for group #{group['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_cloud_access(args)
    usage = "Usage: morpheus roles update-global-cloud-access [role] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update global cloud access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, custom or none.
Only applicable to Tenant roles.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'ComputeZone', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global cloud access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_cloud_access(args)
    options = {}
    cloud_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'read', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role]")
      opts.on( '-c', '--cloud CLOUD', "Cloud name or id" ) do |val|
        cloud_id = val
      end
      opts.on( nil, '--all', "Update all clouds at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update role access for a cloud or all clouds.
[role] is required. This is the name or id of a role.
--cloud or --all is required. This is the name or id of a cloud.
--access is required. This is the new access value: #{ored_list(allowed_access_values)}
Only applicable to Tenant roles and when global cloud access is set to "custom".
EOT
    end
    optparse.parse!(args)

    # usage: update-cloud-access [role] [access] --all
    #        update-cloud-access [role] [cloud] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      cloud_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !cloud_id && !do_all
      raise_command_error("missing required argument: [cloud] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      if role_json['globalZoneAccess'] != 'custom'
        print "\n", red, "Global Cloud Access is currently: #{role_json['globalZoneAccess'].capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-cloud-access \"#{name}\" custom`"
        print "\n\n", reset
        exit 1
      end

      cloud = nil
      if !do_all
        cloud = find_cloud_by_name_or_id_for_provisioning(nil, cloud_id)
        return 1 if cloud.nil?
        cloud_id = cloud['id']
      end
      params = {}
      if do_all
        params['allClouds'] = true
      else
        params['cloudId'] = cloud_id
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_cloud(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_cloud(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all clouds"
        else
          print_green_success "Role #{role['authority']} access updated for cloud #{cloud['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_instance_type_access(args)
    usage = "Usage: morpheus roles update-global-instance-type-access [role] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update global instance type access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, custom or none.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'InstanceType', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global instance type access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_instance_type_access(args)
    options = {}
    instance_type_name = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [type] [access]")
      opts.on( '--instance-type INSTANCE_TYPE', String, "Instance Type name" ) do |val|
        instance_type_name = val
      end
      opts.on( nil, '--all', "Update all instance types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for an instance type or all instance types.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--instance-type or --all is required. This is the name of an instance type.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end
    name = args[0]
    # support old usage: [role] [instance-type] [access]
    instance_type_name ||= args[1]
    access_value ||= args[2]

    if (!instance_type_name && !do_all) || !access_value
      puts optparse
      return 1
    end
    
    access_value = access_value.to_s.downcase

    if !['full', 'none'].include?(access_value)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      if role_json['globalInstanceTypeAccess'] != 'custom'
        print "\n", red, "Global Instance Type Access is currently: #{role_json['globalInstanceTypeAccess'].capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-instance-type-access \"#{name}\" custom`"
        print "\n\n", reset
        return 1
      end

      instance_type = nil
      if !do_all
        instance_type = find_instance_type_by_name(instance_type_name)
        return 1 if instance_type.nil?
      end

      params = {}
      if do_all
        params['allInstanceTypes'] = true
      else
        params['instanceTypeId'] = instance_type['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_instance_type(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_instance_type(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all instance types"
        else
          print_green_success "Role #{role['authority']} access updated for instance type #{instance_type['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_blueprint_access(args)
    usage = "Usage: morpheus roles update-global-blueprint-access [role] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update global blueprint access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, custom or none.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'AppTemplate', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global blueprint access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_blueprint_access(args)
    options = {}
    blueprint_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [blueprint] [access]")
      opts.on( '--blueprint ID', String, "Blueprint ID or Name" ) do |val|
        blueprint_id = val
      end
      opts.on( nil, '--all', "Update all blueprints at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a blueprint or all blueprints.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--blueprint or --all is required. This is the name or id of a blueprint.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-blueprint-access [role] [access] --all
    #        update-blueprint-access [role] [blueprint] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      blueprint_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !blueprint_id && !do_all
      raise_command_error("missing required argument: [blueprint] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      blueprint_global_access = role_json['globalAppTemplateAccess'] || role_json['globalBlueprintAccess']
      blueprint_permissions = role_json['appTemplatePermissions'] || role_json['blueprintPermissions'] || []
      if blueprint_global_access != 'custom'
        print "\n", red, "Global Blueprint Access is currently: #{blueprint_global_access.to_s.capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-blueprint-access \"#{name}\" custom`"
        print "\n\n", reset
        return 1
      end

      # hacky, but support name or code lookup via the list returned in the show payload
      blueprint = nil
      if !do_all
        if blueprint_id.to_s =~ /\A\d{1,}\Z/
          blueprint = blueprint_permissions.find {|b| b['id'] == blueprint_id.to_i }
        else
          blueprint = blueprint_permissions.find {|b| b['name'] == blueprint_id || b['code'] == blueprint_id }
        end
        if blueprint.nil?
          print_red_alert "Blueprint not found: '#{blueprint_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allAppTemplates'] = true
        #params['allBlueprints'] = true
      else
        params['appTemplateId'] = blueprint['id']
        # params['blueprintId'] = blueprint['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_blueprint(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_blueprint(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all blueprints"
        else
          print_green_success "Role #{role['authority']} access updated for blueprint #{blueprint['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_catalog_item_type_access(args)
    usage = "Usage: morpheus roles update-global-catalog-item-type-access [role] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update global catalog item type access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, custom or none.
EOT
    end
    optparse.parse!(args)

    if args.count < 2
      puts optparse
      exit 1
    end
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      puts optparse
      exit 1
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?

      params = {permissionCode: 'CatalogItemType', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global catalog item type access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_catalog_item_type_access(args)
    options = {}
    catalog_item_type_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [catalog-item-type] [access]")
      opts.on( '--catalog-item-type ID', String, "Catalog Item Type ID or Name" ) do |val|
        catalog_item_type_id = val
      end
      opts.on( nil, '--all', "Update all catalog item types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a catalog item type or all types.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--catalog-item-type or --all is required. This is the name or id of a catalog item type.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-catalog_item_type-access [role] [access] --all
    #        update-catalog_item_type-access [role] [catalog-item-type] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      catalog_item_type_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !catalog_item_type_id && !do_all
      raise_command_error("missing required argument: [catalog-item-type] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      catalog_item_type_global_access = role_json['globalCatalogItemTypeAccess']
      catalog_item_type_permissions = role_json['catalogItemTypePermissions'] || role_json['catalogItemTypes'] []
      if catalog_item_type_global_access != 'custom'
        print "\n", red, "Global Catalog Item Type Access is currently: #{catalog_item_type_global_access.to_s.capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-catalog-item-type-access \"#{name}\" custom`"
        print "\n\n", reset
        return 1
      end

      # hacky, but support name or code lookup via the list returned in the show payload
      catalog_item_type = nil
      if !do_all
        if catalog_item_type_id.to_s =~ /\A\d{1,}\Z/
          catalog_item_type = catalog_item_type_permissions.find {|b| b['id'] == catalog_item_type_id.to_i }
        else
          catalog_item_type = catalog_item_type_permissions.find {|b| b['name'] == catalog_item_type_id }
        end
        if catalog_item_type.nil?
          print_red_alert "Catalog Item Type not found: '#{catalog_item_type_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allCatalogItemTypes'] = true
      else
        params['catalogItemTypeId'] = catalog_item_type['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_catalog_item_type(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_catalog_item_type(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all catalog item types"
        else
          print_green_success "Role #{role['authority']} access updated for catalog item type #{catalog_item_type['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_persona_access(args)
    options = {}
    persona_id = nil
    name = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [persona] [access]")
      opts.on( '--persona CODE', String, "Persona Code" ) do |val|
        persona_id = val
      end
      opts.on( nil, '--all', "Update all personas at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a persona or all personas.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--persona or --all is required. This is the code of a persona. Service Catalog, Standard, or Virtual Desktop\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-persona-access [role] [access] --all
    #        update-persona-access [role] [persona] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      persona_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !persona_id && !do_all
      raise_command_error("missing required argument: [persona] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      
      # no lookup right now, pass the code serviceCatalog|standard
      persona_code = persona_id

      params = {}
      if do_all
        params['allPersonas'] = true
      else
        params['personaCode'] = persona_code
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_persona(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_persona(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all personas"
        else
          print_green_success "Role #{role['authority']} access updated for persona #{persona_code}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_vdi_pool_access(args)
    usage = "Usage: morpheus roles update-global-vdi-pool-access [role] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update global VDI pool access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, custom or none.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 2)
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      raise_command_error("invalid access value: #{args[1]}", args, optparse)
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      # note: VdiPools being plural is odd, the others are singular
      params = {permissionCode: 'VdiPools', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global vdi pool access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_vdi_pool_access(args)
    options = {}
    vdi_pool_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [vdi-pool] [access]")
      opts.on( '--vdi-pool ID', String, "VDI Pool ID or Name" ) do |val|
        vdi_pool_id = val
      end
      opts.on( nil, '--all', "Update all VDI pools at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a VDI pool or all VDI pools.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--vdi-pool or --all is required. This is the name or id of a VDI pool.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-vdi-pool-access [role] [access] --all
    #        update-vdi-pool-access [role] [vdi-pool] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      vdi_pool_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !vdi_pool_id && !do_all
      raise_command_error("missing required argument: [vdi-pool] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      vdi_pool_global_access = role_json['globalVdiPoolAccess']
      vdi_pool_permissions = role_json['vdiPoolPermissions'] || role_json['vdiPools'] || []
      if vdi_pool_global_access != 'custom'
        print "\n", red, "Global VDI Pool Access is currently: #{vdi_pool_global_access.to_s.capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-vdi-pool-access \"#{name}\" custom`"
        print "\n\n", reset
        return 1
      end

      # hacky, but support name or code lookup via the list returned in the show payload
      vdi_pool = nil
      if !do_all
        if vdi_pool_id.to_s =~ /\A\d{1,}\Z/
          vdi_pool = vdi_pool_permissions.find {|b| b['id'] == vdi_pool_id.to_i }
        else
          vdi_pool = vdi_pool_permissions.find {|b| b['name'] == vdi_pool_id }
        end
        if vdi_pool.nil?
          print_red_alert "VDI Pool not found: '#{vdi_pool_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allVdiPools'] = true
      else
        params['vdiPoolId'] = vdi_pool['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_vdi_pool(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_vdi_pool(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all VDI pools"
        else
          print_green_success "Role #{role['authority']} access updated for VDI pool #{vdi_pool['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_global_report_type_access(args)
    usage = "Usage: morpheus roles update-global-report-type-access [role] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = <<-EOT
Update global report type access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, custom or none.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 2)
    name = args[0]
    access_value = args[1].to_s.downcase
    if !['full', 'custom', 'none'].include?(access_value)
      raise_command_error("invalid access value: #{args[1]}", args, optparse)
    end


    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      exit 1 if role.nil?
      # note: ReportTypes being plural is odd, the others are singular
      params = {permissionCode: 'ReportTypes', access: access_value}
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_permission(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_permission(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Role #{role['authority']} global report type access updated"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_report_type_access(args)
    options = {}
    report_type_id = nil
    access_value = nil
    do_all = false
    allowed_access_values = ['full', 'none']
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[role] [report-type] [access]")
      opts.on( '--report-type ID', String, "Report Type ID or Name" ) do |val|
        report_type_id = val
      end
      opts.on( nil, '--all', "Update all report types at once." ) do
        do_all = true
      end
      opts.on( '--access VALUE', String, "Access value [#{allowed_access_values.join('|')}]" ) do |val|
        access_value = val
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Update role access for a report type or all report types.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--report-type or --all is required. This is the name or id of a report type.\n" + 
                    "--access is required. This is the new access value: #{ored_list(allowed_access_values)}"
    end
    optparse.parse!(args)

    # usage: update-report-type-access [role] [access] --all
    #        update-report-type-access [role] [report-type] [access]
    name = args[0]
    if do_all
      verify_args!(args:args, optparse:optparse, min:1, max:2)
      access_value = args[1] if args[1]
    else
      verify_args!(args:args, optparse:optparse, min:1, max:3)
      report_type_id = args[1] if args[1]
      access_value = args[2] if args[2]
    end
    if !report_type_id && !do_all
      raise_command_error("missing required argument: [report-type] or --all", args, optparse)
    end
    if !access_value
      raise_command_error("missing required argument: [access]", args, optparse)
    end
    access_value = access_value.to_s.downcase
    if !allowed_access_values.include?(access_value)
      raise_command_error("invalid access value: #{access_value}", args, optparse)
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      role = find_role_by_name_or_id(account_id, name)
      return 1 if role.nil?

      role_json = @roles_interface.get(account_id, role['id'])
      report_type_global_access = role_json['globalReportTypeAccess']
      report_type_permissions = role_json['reportTypePermissions'] || role_json['reportTypes'] || []
      if report_type_global_access != 'custom'
        print "\n", red, "Global Report Type Access is currently: #{report_type_global_access.to_s.capitalize}"
        print "\n", "You must first set it to Custom via `morpheus roles update-global-report-type-access \"#{name}\" custom`"
        print "\n\n", reset
        return 1
      end

      # hacky, but support name or code lookup via the list returned in the show payload
      report_type = nil
      if !do_all
        if report_type_id.to_s =~ /\A\d{1,}\Z/
          report_type = report_type_permissions.find {|b| b['id'] == report_type_id.to_i }
        else
          report_type = report_type_permissions.find {|b| b['name'] == report_type_id }
        end
        if report_type.nil?
          print_red_alert "Report Type not found: '#{report_type_id}'"
          return 1
        end
      end

      params = {}
      if do_all
        params['allReportTypes'] = true
      else
        params['reportTypeId'] = report_type['id']
      end
      params['access'] = access_value
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update_report_type(account_id, role['id'], params)
        return
      end
      json_response = @roles_interface.update_report_type(account_id, role['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if do_all
          print_green_success "Role #{role['authority']} access updated for all report types"
        else
          print_green_success "Role #{role['authority']} access updated for report type #{report_type['name']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private
  
  def add_role_option_types
    [
      {'fieldName' => 'authority', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'roleType', 'fieldLabel' => 'Role Type', 'type' => 'select', 'selectOptions' => [{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}], 'defaultValue' => 'user'},
      {'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'text'},
      {'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use'},
      {'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it.'},
      {'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'selectOptions' => get_persona_select_options(), 'description' => 'Default Persona'}
    ]
  end

  def update_role_option_types
    add_role_option_types.reject {|it| ['roleType', 'baseRole'].include?(it['fieldName']) }
  end

  def role_type_options
    [{'name' => 'User Role', 'value' => 'user'}, {'name' => 'Account Role', 'value' => 'account'}]
  end

  def get_persona_select_options
    [
      {'name'=>'Service Catalog','value'=>'serviceCatalog'},
      {'name'=>'Standard','value'=>'standard'},
      {'name'=>'Virtual Desktop','value'=>'vdi'}
    ]
  end

  def role_owner_options
    @options_interface.options_for_source("tenants", {})['data']
  end

  def base_role_options(role_payload)
    params = {"tenantId" => role_payload['owner'], "userId" => current_user['id'], "roleType" => role_payload['roleType'] }
    @options_interface.options_for_source("copyFromRole", params)['data']
  end

  def has_complete_access
    has_access = false
    if @is_master_account
      admin_accounts = @user_permissions.select { |it| it['code'] == 'admin-accounts' && it['access'] == 'full'}
      admin_roles = @user_permissions.select { |it| it['code'] == 'admin-roles' && it['access'] == 'full' }
      if admin_accounts != nil && admin_roles != nil
        has_access = true
      end
    end
    has_access 
  end

  def parse_access_csv(output, val, args, optparse)
    output ||= {}
    val.split(",").each do |value_pair|
      # split on '=' only because ':' is included in the permission name
      k,v = value_pair.include?("=") ? value_pair.strip.split("=") : [value_pair, ""]
      k.strip!
      v.strip!
      if v == "" 
        raise_command_error "permission '#{k}=#{v}' is invalid. The access code must be a value like [none|read|full]", args, optparse
      end
      output[k] = v
    end
    return output
  end
end
