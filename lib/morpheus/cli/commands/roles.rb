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
      if json_response['globalInstanceTypeAccess'] == 'custom'
        print_h2 "Instance Type Access", options
        if options[:include_instance_type_access]
          rows = json_response['instanceTypePermissions'].collect do |it|
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
      blueprint_permissions = json_response['appTemplatePermissions'] || json_response['blueprintPermissions'] || []
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
      catalog_item_type_permissions = json_response['catalogItemTypePermissions'] || []
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
      

      persona_permissions = json_response['personaPermissions'] || json_response['personas'] || []
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
      vdi_pool_permissions = json_response['vdiPoolPermissions'] || []
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
      report_type_permissions = json_response['reportTypePermissions'] || []
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
      print_h1 "Role Permissions: [#{role['id']}] #{role['authority']}", options

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
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
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

        if @is_master_account
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleType', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => role_type_options, 'defaultValue' => 'user', 'displayOrder' => 3}], options[:options])
          role_payload['roleType'] = v_prompt['roleType']
        else
          role_payload['roleType'] = 'user'
        end

        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'baseRole', 'fieldLabel' => 'Copy From Role', 'type' => 'text', 'displayOrder' => 4}], options[:options])
        if v_prompt['baseRole'].to_s != ''
          base_role = find_role_by_name_or_id(account_id, v_prompt['baseRole'])
          exit 1 if base_role.nil?
          role_payload['baseRoleId'] = base_role['id']
        end

        if @is_master_account
          if role_payload['roleType'] == 'user'
            v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenant', 'fieldLabel' => 'Multitenant', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'A Multitenant role is automatically copied into all existing subaccounts as well as placed into a subaccount when created. Useful for providing a set of predefined roles a Customer can use', 'displayOrder' => 5}], options[:options])
            role_payload['multitenant'] = ['on','true'].include?(v_prompt['multitenant'].to_s)
            if role_payload['multitenant']
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it. '}], options[:options])
              role_payload['multitenantLocked'] = ['on','true'].include?(v_prompt['multitenantLocked'].to_s)
            end
          end
        end

        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'optionSource' => 'personas', 'description' => 'Default Persona'}], options[:options], @api_client)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona', 'type' => 'select', 'selectOptions' => get_persona_select_options(), 'description' => 'Default Persona'}], options[:options], @api_client)
        role_payload['defaultPersona'] = {'code' => v_prompt['defaultPersona']} unless v_prompt['defaultPersona'].to_s.strip.empty?

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
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      exit 1
    end
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

        if params.empty?
          puts optparse
          option_lines = prompt_option_types.collect {|it| "\t-O #{it['fieldName']}=\"value\"" }.join("\n")
          puts "\nAvailable Options:\n#{option_lines}\n\n"
          exit 1
        end

        payload = {"role" => params}
      end
      @roles_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @roles_interface.dry.update(account_id, role['id'], payload)
        return
      end
      json_response = @roles_interface.update(account_id, role['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      role = json_response['role']
      display_name = role['authority'] rescue ''
      print_green_success "Updated role #{display_name}"

      get_args = [role['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
      if account
        get_args.push "--account-id", account['id'].to_s
      end
      get(get_args)

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
    usage = "Usage: morpheus roles update-feature-access [name] [code] [full|read|user|yes|no|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [code] [full|read|user|yes|no|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)

    if args.count < 3
      puts optparse
      exit 1
    end
    name = args[0]
    permission_code = args[1]
    access_value = args[2].to_s.downcase

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
    usage = "Usage: morpheus roles update-global-group-access [name] [full|read|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [full|read|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update global group access for a role.
[role] is required. This is the name (authority) or id of a role.
[access] is required. This is the access level to assign: full, read, custom or none.
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
      opts.footer = "Update role access for a group or all groups.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--group or --all is required. This is the name or id of a group.\n" + 
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
    usage = "Usage: morpheus roles update-global-cloud-access [name] [full|custom|none]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [full|custom|none]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
            opts.footer = <<-EOT
Update global cloud access for a role.
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
      opts.banner = subcommand_usage("[name]")
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
      opts.footer = "Update role access for a cloud or all clouds.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--cloud or --all is required. This is the name or id of a cloud.\n" + 
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
      opts.footer = "Update role access for an blueprint or all blueprints.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--blueprint or --all is required. This is the name or id of a blueprint.\n" + 
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
      opts.footer = "Update role access for an catalog item type or all types.\n" +
                    "[role] is required. This is the name or id of a role.\n" + 
                    "--catalog-item-type or --all is required. This is the name or id of a catalog item type.\n" + 
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
      catalog_item_type_permissions = role_json['catalogItemTypePermissions'] || []
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
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
      vdi_pool_permissions = role_json['vdiPoolPermissions'] || []
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
                    "--access is required. This is the new access value. #{anded_list(allowed_access_values)}"
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
      report_type_permissions = role_json['reportTypePermissions'] || []
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
      {'fieldName' => 'multitenantLocked', 'fieldLabel' => 'Multitenant Locked', 'type' => 'checkbox', 'defaultValue' => 'off', 'description' => 'Prevents subtenants from branching off this role/modifying it. '},
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

end
