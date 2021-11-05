require 'morpheus/cli/cli_command'
require 'date' #needed?

class Morpheus::Cli::InvoicesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'invoices'

  register_subcommands :list, :get, :update, :refresh,
                       :list_line_items, :get_line_item
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @invoices_interface = @api_client.invoices
    @invoice_line_items_interface = @api_client.invoice_line_items
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-a', '--all', "Display all details, costs and prices." ) do
        options[:show_all] = true
        options[:show_dates] = true
        options[:show_estimates] = true
        options[:show_costs] = true
      end
      opts.on('--dates', "Display Ref Start, Ref End, etc.") do |val|
        options[:show_dates] = true
      end
      opts.on('--costs', '--costs', "Display Costs in addition to prices" ) do
        options[:show_costs] = true
      end
      opts.on('--estimates', '--estimates', "Display all estimated prices, from usage metering info: Compute, Memory, Storage, Network, Extra" ) do
        options[:show_estimates] = true
      end
      opts.on('-t', '--type TYPE', "Filter by Ref Type eg. ComputeSite (Group), ComputeZone (Cloud), ComputeServer (Host), Instance, Container, User") do |val|
        params['refType'] ||= []
        values = val.split(",").collect {|it| it.strip }.select {|it| it != "" }
        values.each { |it| params['refType'] << parse_invoice_ref_type(it) }
      end
      opts.on('--id ID', String, "Filter by Ref ID") do |val|
        ref_ids << val
      end
      opts.on('--ref-id ID', String, "Filter by Ref ID") do |val|
        ref_ids << val
      end
      opts.add_hidden_option('--ref-id')
      opts.on('--group ID', String, "Filter by Group") do |val|
        options[:groups] ||= []
        options[:groups] << val
      end
      opts.on( '-c', '--cloud CLOUD', "Filter by Cloud" ) do |val|
        options[:clouds] ||= []
        options[:clouds] << val
      end
      opts.on('--instance ID', String, "Filter by Instance") do |val|
        options[:instances] ||= []
        options[:instances] << val
      end
      opts.on('--container ID', String, "Filter by Container") do |val|
        params['containerId'] ||= []
        params['containerId'] << val
      end
      opts.on('--server ID', String, "Filter by Server (Host)") do |val|
        options[:servers] ||= []
        options[:servers] << val
      end
      opts.on('--user ID', String, "Filter by User") do |val|
        options[:users] ||= []
        options[:users] << val
      end
      opts.on('--project PROJECT', String, "View invoices for a project.") do |val|
        options[:projects] ||= []
        options[:projects] << val
      end
      # opts.on('--cluster ID', String, "Filter by Cluster") do |val|
      #   params['clusterId'] ||= []
      #   params['clusterId'] << val
      # end
      opts.on('--start DATE', String, "Start date in the format YYYY-MM-DD.") do |val|
        params['startDate'] = val #parse_time(val).utc.iso8601
      end
      opts.on('--end DATE', String, "End date in the format YYYY-MM-DD. Default is now.") do |val|
        params['endDate'] = val #parse_time(val).utc.iso8601
      end
      opts.on('--period PERIOD', String, "Period in the format YYYYMM. This can be used instead of start/end.") do |val|
        params['period'] = parse_period(val)
      end
      opts.on('--active [true|false]',String, "Filter by active.") do |val|
        params['active'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--estimate [true|false]',String, "Filter by estimate.") do |val|
        params['estimate'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--tenant ID', String, "View invoices for a tenant. Default is your own account.") do |val|
        params['accountId'] = val
      end
      opts.on('--tags Name=Value',String, "Filter by tags.") do |val|
        val.split(",").each do |value_pair|
          k,v = value_pair.strip.split("=")
          options[:tags] ||= {}
          options[:tags][k] ||= []
          options[:tags][k] << (v || '')
        end
      end
      opts.on('--totals', "View total costs and prices for all the invoices found.") do |val|
        params['includeTotals'] = true
        options[:show_invoice_totals] = true
      end
      opts.on('--totals-only', "View totals only") do |val|
        params['includeTotals'] = true
        options[:show_invoice_totals] = true
        options[:totals_only] = true
      end
      opts.on('--sigdig DIGITS', "Significant digits when rounding cost values for display as currency. Default is 2. eg. $3.50") do |val|
        options[:sigdig] = val.to_i
      end
      build_standard_list_options(opts, options)
      opts.footer = "List invoices."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    # construct params
    params.merge!(parse_list_options(options))
    if options[:clouds]
      cloud_ids = parse_cloud_id_list(options[:clouds], {}, false, true)
      return 1, "clouds not found for #{options[:clouds]}" if cloud_ids.nil?
      params['zoneId'] = cloud_ids
    end
    if options[:groups]
      group_ids = parse_group_id_list(options[:groups], {}, false, true)
      return 1, "groups not found for #{options[:groups]}" if group_ids.nil?
      params['siteId'] = group_ids
    end
    if options[:instances]
      instance_ids = parse_instance_id_list(options[:instances], {}, false, true)
      return 1, "instances not found for #{options[:instances]}" if instance_ids.nil?
      params['instanceId'] = instance_ids
    end
    if options[:servers]
      server_ids = parse_server_id_list(options[:servers], {}, false, true)
      return 1, "servers not found for #{options[:servers]}" if server_ids.nil?
      params['serverId'] = server_ids
    end
    if options[:users]
      user_ids = parse_user_id_list(options[:users], {}, false, true)
      return 1, "users not found for #{options[:users]}" if user_ids.nil?
      params['userId'] = user_ids
    end
    if options[:projects]
      project_ids = parse_project_id_list(options[:projects], {}, false, true)
      return 1, "projects not found for #{options[:projects]}" if project_ids.nil?
      params['projectId'] = project_ids
    end
    params['refId'] = ref_ids unless ref_ids.empty?
    if options[:tags] && !options[:tags].empty?
      options[:tags].each do |k,v|
        params['tags.' + k] = v
      end
    end
    @invoices_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @invoices_interface.dry.list(params)
      return
    end
    json_response = @invoices_interface.list(params)
    invoices = json_response['invoices']
    render_response(json_response, options, 'invoices') do
      title = "Morpheus Invoices"
      subtitles = []
      if params['startDate']
        subtitles << "Start Date: #{params['startDate']}"
      end
      if params['endDate']
        subtitles << "End Date: #{params['endDate']}"
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if invoices.empty?
        print cyan,"No invoices found.",reset,"\n"
        print reset,"\n"
      else
        # current_date = Time.now
        # current_period = "#{current_date.year}#{current_date.month.to_s.rjust(2, '0')}"
        show_projects = invoices.find {|it| it['project'] } || (params['projectId'] || params['projectName'] || params['projectTag'])
        columns = [
          {"INVOICE ID" => lambda {|it| it['id'] } },
          {"TYPE" => lambda {|it| format_invoice_ref_type(it) } },
          {"REF ID" => lambda {|it| it['refId'] } },
          {"REF UUID" => lambda {|it| it['refUuid'] } },
          {"REF NAME" => lambda {|it| 
            if options[:show_all]
              it['refName']
            else
              truncate_string_right(it['refName'], 100)
            end
          } },
          #{"INTERVAL" => lambda {|it| it['interval'] } },
          {"CLOUD" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' } },
          #{"TENANT" => lambda {|it| it['account'] ? it['account']['name'] : '' } },
          
          #{"COST TYPE" => lambda {|it| it['costType'].to_s.capitalize } },
          {"PERIOD" => lambda {|it| format_invoice_period(it) } },
          {"START" => lambda {|it| format_date(it['startDate']) } },
          {"END" => lambda {|it| format_date(it['endDate']) } },
        ] + ((options[:show_dates] || options[:show_all]) ? [
          {"REF START" => lambda {|it| format_dt(it['refStart']) } },
          {"REF END" => lambda {|it| format_dt(it['refEnd']) } },
          # {"LAST COST DATE" => lambda {|it| format_local_dt(it['lastCostDate']) } },
          # {"LAST ACTUAL DATE" => lambda {|it| format_local_dt(it['lastActualDate']) } },
        ] : []) + [
          {"COMPUTE PRICE" => lambda {|it| format_money(it['computePrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"MEMORY PRICE" => lambda {|it| format_money(it['memoryPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"STORAGE PRICE" => lambda {|it| format_money(it['storagePrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"NETWORK PRICE" => lambda {|it| format_money(it['networkPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"EXTRA PRICE" => lambda {|it| format_money(it['extraPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"MTD PRICE" => lambda {|it| format_money(it['runningPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"TOTAL PRICE" => lambda {|it| 
            format_money(it['totalPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) + ((it['totalCost'].to_f > 0 && it['totalCost'] != it['runningCost']) ? " (Projected)" : "")
          } }
        ]
        
        if options[:show_costs] && json_response['masterAccount'] != false
          columns += [
          {"COMPUTE COST" => lambda {|it| format_money(it['computeCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"MEMORY COST" => lambda {|it| format_money(it['memoryCost']) } },
          {"STORAGE COST" => lambda {|it| format_money(it['storageCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"NETWORK COST" => lambda {|it| format_money(it['networkCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"EXTRA COST" => lambda {|it| format_money(it['extraCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"MTD COST" => lambda {|it| format_money(it['runningCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"TOTAL COST" => lambda {|it| 
            format_money(it['totalCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) + ((it['totalCost'].to_f > 0 && it['totalCost'] != it['runningCost']) ? " (Projected)" : "")
          } }
        ]
        end
        if options[:show_estimates]
          columns += [
            {"METERED COMPUTE PRICE" => lambda {|it| format_money(it['estimatedComputePrice'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
            {"METERED MEMORY PRICE" => lambda {|it| format_money(it['estimatedMemoryPrice'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
            {"METERED STORAGE PRICE" => lambda {|it| format_money(it['estimatedStoragePrice'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
            {"METERED NETWORK PRICE" => lambda {|it| format_money(it['estimatedNetworkPrice'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
            {"METERED EXTRA PRICE" => lambda {|it| format_money(it['estimatedExtraPrice'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
            {"METERED MTD PRICE" => lambda {|it| format_money(it['estimatedRunningPrice'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
            {"METERED TOTAL PRICE" => lambda {|it| 
              format_money(it['estimatedTotalPrice'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) + ((it['estimatedTotalPrice'].to_f > 0 && it['estimatedTotalPrice'] != it['estimatedRunningPrice']) ? " (Projected)" : "")
            } },
          ]
          if options[:show_costs] && json_response['masterAccount'] != false
            columns += [
              {"METERED COMPUTE COST" => lambda {|it| format_money(it['estimatedComputeCost'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
              {"METERED MEMORY COST" => lambda {|it| format_money(it['estimatedMemoryCost'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
              {"METERED STORAGE COST" => lambda {|it| format_money(it['estimatedStorageCost'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
              {"METERED NETWORK COST" => lambda {|it| format_money(it['estimatedNetworkCost'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
              {"METERED EXTRA COST" => lambda {|it| format_money(it['estimatedExtraCost'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
              {"METERED MTD COST" => lambda {|it| format_money(it['estimatedRunningCost'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) } },
              {"METERED TOTAL COST" => lambda {|it| 
                format_money(it['estimatedTotalCost'], it['estimatedCurrency'] || 'USD', {sigdig:options[:sigdig]}) + ((it['estimatedTotalCost'].to_f > 0 && it['estimatedTotalCost'] != it['estimatedRunningCost']) ? " (Projected)" : "")
              } },
            ]
          end
        end
        columns += [
          {"ESTIMATE" => lambda {|it| format_boolean(it['estimate']) } },
          {"ACTIVE" => lambda {|it| format_boolean(it['active']) } },
          {"ITEMS" => lambda {|it| (it['lineItemCount'] ? it['lineItemCount'] : it['lineItems'].size) rescue '' } },
          {"TAGS" => lambda {|it| (it['metadata'] || it['tags']) ? (it['metadata'] || it['tags']).collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' } },
        ]
        if show_projects
          columns += [
          {"PROJECT ID" => lambda {|it| it['project'] ? it['project']['id'] : '' } },
          {"PROJECT NAME" => lambda {|it| it['project'] ? it['project']['name'] : '' } },
          {"PROJECT TAGS" => lambda {|it| it['project'] ? truncate_string(format_metadata(it['project']['tags']), 50) : '' } },
        ]
        end
        if options[:show_dates]
          columns += [
            {"LAST COST DATE" => lambda {|it| format_local_dt(it['lastCostDate']) } },
            {"LAST ACTUAL DATE" => lambda {|it| format_local_dt(it['lastActualDate']) } },
          ]
        end
        columns += [
          {"CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } },
          {"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
        ]
        unless options[:totals_only]
          print as_pretty_table(invoices, columns, options)
          print_results_pagination(json_response, {:label => "invoice", :n_label => "invoices"})
        end

        if options[:show_invoice_totals]
          invoice_totals = json_response['invoiceTotals']
          print_h2 "Invoice Totals (#{format_number(json_response['meta']['total']) rescue ''})"

          if invoice_totals
            cost_rows = [
              {label: 'Price'.upcase, compute: invoice_totals['actualComputePrice'], memory: invoice_totals['actualMemoryPrice'], storage: invoice_totals['actualStoragePrice'], network: invoice_totals['actualNetworkPrice'], license: invoice_totals['actualLicensePrice'], extra: invoice_totals['actualExtraPrice'], running: invoice_totals['actualRunningPrice'], total: invoice_totals['actualTotalPrice'], currency: invoice_totals['actualCurrency']},
            ]
            if options[:show_costs]
              cost_rows += [
                {label: 'Cost'.upcase, compute: invoice_totals['actualComputeCost'], memory: invoice_totals['actualMemoryCost'], storage: invoice_totals['actualStorageCost'], network: invoice_totals['actualNetworkCost'], license: invoice_totals['actualLicenseCost'], extra: invoice_totals['actualExtraCost'], running: invoice_totals['actualRunningCost'], total: invoice_totals['actualTotalCost'], currency: invoice_totals['actualCurrency']}
              ]
            end
            if options[:show_estimates]
              cost_rows += [
                {label: 'Metered Price'.upcase, compute: invoice_totals['estimatedComputePrice'], memory: invoice_totals['estimatedMemoryPrice'], storage: invoice_totals['estimatedStoragePrice'], network: invoice_totals['estimatedNetworkPrice'], license: invoice_totals['estimatedLicensePrice'], extra: invoice_totals['estimatedExtraPrice'], running: invoice_totals['estimatedRunningPrice'], total: invoice_totals['estimatedTotalPrice'], currency: invoice_totals['estimatedCurrency']}
              ]
              if options[:show_costs]
                cost_rows += [
                  {label: 'Metered Cost'.upcase, compute: invoice_totals['estimatedComputeCost'], memory: invoice_totals['estimatedMemoryCost'], storage: invoice_totals['estimatedStorageCost'], network: invoice_totals['estimatedNetworkCost'], license: invoice_totals['estimatedLicenseCost'], extra: invoice_totals['estimatedExtraCost'], running: invoice_totals['estimatedRunningCost'], total: invoice_totals['estimatedTotalCost'], currency: invoice_totals['estimatedCurrency']}
                ]
              end
            end
            cost_columns = {
              "" => lambda {|it| it[:label] },
              "Compute" => lambda {|it| format_money(it[:compute], it[:currency] || it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
              "Memory" => lambda {|it| format_money(it[:memory], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
              "Storage" => lambda {|it| format_money(it[:storage], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
              "Network" => lambda {|it| format_money(it[:network], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
              "License" => lambda {|it| format_money(it[:license], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
              "Extra" => lambda {|it| format_money(it[:extra], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
              "MTD" => lambda {|it| format_money(it[:running], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
              "Total" => lambda {|it| 
                format_money(it[:total], it[:currency] || 'USD', {sigdig:options[:sigdig]}) + ((it[:total].to_f > 0 && it[:total] != it[:running]) ? " (Projected)" : "")
              },
              "Currency" => lambda {|it| it[:currency] },
            }.upcase_keys!
            # remove columns that rarely have data...
            if cost_rows.sum { |it| it[:memory].to_f } == 0
              cost_columns.delete("Memory".upcase)
            end
            if cost_rows.sum { |it| it[:license].to_f } == 0
              cost_columns.delete("License".upcase)
            end
            if cost_rows.sum { |it| it[:extra].to_f } == 0
              cost_columns.delete("Extra".upcase)
            end
            print as_pretty_table(cost_rows, cost_columns, options)
          else
            print "\n"
            print yellow, "No invoice totals data", reset, "\n"
          end
        end
        print reset,"\n"
      end
      return 0, nil
    end
  end
  
  def get(args)
    options, params = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('-a', '--all', "Display all details, costs and prices." ) do
        options[:show_estimates] = true
        options[:show_costs] = true
        options[:max_line_items] = 10000
      end
      opts.on('--estimates', '--estimates', "Display all estimated prices, from usage metering info: Compute, Memory, Storage, Network, Extra" ) do
        options[:show_estimates] = true
      end
      opts.on('--costs', '--costs', "Display Costs in addition to prices" ) do
        options[:show_costs] = true
      end
      opts.on('--no-line-items', '--no-line-items', "Do not display line items.") do |val|
        options[:hide_line_items] = true
      end
      opts.on('--sigdig DIGITS', "Significant digits when rounding cost values for display as currency. Default is 2. eg. $3.50") do |val|
        options[:sigdig] = val.to_i
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific invoice.
[id] is required. This is the id of an invoice.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    @invoices_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @invoices_interface.dry.get(id, params)
      return
    end
    json_response = @invoices_interface.get(id, params)
    if options[:hide_line_items]
      json_response['invoice'].delete('lineItems') rescue nil
    end
    render_response(json_response, options, invoice_object_key) do
      invoice = json_response[invoice_object_key]
      print_h1 "Invoice Details"
      print cyan
      description_cols = {
        "Invoice ID" => lambda {|it| it['id'] },
        "Type" => lambda {|it| format_invoice_ref_type(it) },
        "Ref ID" => lambda {|it| it['refId'] },
        "Ref Name" => lambda {|it| it['refName'] },
        "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Power State" => lambda {|it| format_server_power_state(it) },
        "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Estimate" => lambda {|it| format_boolean(it['estimate']) },
        #"Cost Type" => lambda {|it| it['costType'].to_s.capitalize },
        "Period" => lambda {|it| format_invoice_period(it) },
        #"Interval" => lambda {|it| it['interval'] },
        "Start" => lambda {|it| format_date(it['startDate']) },
        "End" => lambda {|it| format_date(it['endDate']) },
        "Ref Start" => lambda {|it| format_dt(it['refStart']) },
        "Ref End" => lambda {|it| format_dt(it['refEnd']) },
        "Currency" => lambda {|it| (it['estimate'] ? it['estimatedCurrency'] : it['currency']) || 'USD' },
        "Conversion Rate" => lambda {|it| (it['estimate'] ? it['estimatedConversionRate'] : it['conversionRate']) },
        # "Estimated Currency" => lambda {|it| it['estimatedCurrency'] },
        # "Estimated Conversion Rate" => lambda {|it| it['estimatedConversionRate'] },
        "Items" => lambda {|it| (it['lineItemCount'] ? it['lineItemCount'] : it['lineItems'].size) rescue '' },
        "Tags" => lambda {|it| (it['metadata'] || it['tags']) ? (it['metadata'] || it['tags']).collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' },
        "Project ID" => lambda {|it| it['project'] ? it['project']['id'] : '' },
        "Project Name" => lambda {|it| it['project'] ? it['project']['name'] : '' },
        "Project Tags" => lambda {|it| it['project'] ? format_metadata(it['project']['tags']) : '' },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      # remove columns that do not apply
      if invoice['plan'].nil?
        description_cols.delete("Plan")
      end
      if invoice['project'].nil?
        description_cols.delete("Project ID")
        description_cols.delete("Project Name")
        description_cols.delete("Project Tags")
      end
      tags = (invoice['metadata'] || invoice['tags'])
      if tags.nil? || tags.empty?
        description_cols.delete("Tags")
      end
      if !['ComputeServer','Instance','Container'].include?(invoice['refType'])
        description_cols.delete("Power State")
      end
      # if invoice['currency'].nil? || invoice['currency'] == 'USD'
      #   description_cols.delete("Currency")
      # end
      # if invoice['actualConversionRate'].nil? || invoice['actualConversionRate'] == 1
      #   description_cols.delete("Conversion Rate")
      # end
      print_description_list(description_cols, invoice)

      # Line Items
      line_items = invoice['lineItems']
      if line_items && line_items.size > 0 && options[:hide_line_items] != true
        line_items_columns = [
          {"ID" => lambda {|it| it['id'] } },
          #{"REF TYPE" => lambda {|it| format_invoice_ref_type(it) } },
          #{"REF ID" => lambda {|it| it['refId'] } },
          #{"REF NAME" => lambda {|it| it['refName'] } },
          #{"REF CATEGORY" => lambda {|it| it['refCategory'] } },
          {"START" => lambda {|it| format_dt(it['startDate']) } },
          {"END" => lambda {|it| format_dt(it['endDate']) } },
          {"USAGE TYPE" => lambda {|it| it['usageType'] } },
          {"USAGE CATEGORY" => lambda {|it| it['usageCategory'] } },
          {"USAGE" => lambda {|it| it['itemUsage'] } },
          {"RATE" => lambda {|it| it['itemRate'] } },
          {"UNIT" => lambda {|it| it['rateUnit'] } },
          {"COST" => lambda {|it| format_money(it['itemCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"PRICE" => lambda {|it| format_money(it['itemPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          #{"TAX" => lambda {|it| format_money(it['itemTax'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          # {"TERM" => lambda {|it| it['itemTerm'] } },
          {"ITEM ID" => lambda {|it| truncate_string_right(it['itemId'], 65) } },
          {"ITEM NAME" => lambda {|it| it['itemName'] } },
          {"ITEM TYPE" => lambda {|it| it['itemType'] } },
          {"ITEM DESCRIPTION" => lambda {|it| it['itemDescription'] } },
          {"PRODUCT CODE" => lambda {|it| it['productCode'] } },
          {"CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } },
          {"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } }
        ]
        print_h2 "Line Items"
        #max_line_items = options[:max_line_items] ? options[:max_line_items].to_i : 5
        paged_line_items = line_items #.first(max_line_items)
        print as_pretty_table(paged_line_items, line_items_columns, options)
        print_results_pagination({total: line_items.size, size: paged_line_items.size}, {:label => "line item", :n_label => "line items"})
      end

      print_h2 "Invoice Totals"

      cost_rows = [
        {label: 'Price'.upcase, compute: invoice['computePrice'], memory: invoice['memoryPrice'], storage: invoice['storagePrice'], network: invoice['networkPrice'], license: invoice['licensePrice'], extra: invoice['extraPrice'], running: invoice['runningPrice'], total: invoice['totalPrice'], currency: invoice['currency']},
      ]
      if options[:show_costs] # && json_response['masterAccount'] != false
        cost_rows += [
          {label: 'Cost'.upcase, compute: invoice['computeCost'], memory: invoice['memoryCost'], storage: invoice['storageCost'], network: invoice['networkCost'], license: invoice['licenseCost'], extra: invoice['extraCost'], running: invoice['runningCost'], total: invoice['totalCost'], currency: invoice['currency']},
        ]
      end
      if options[:show_estimates]
        cost_rows += [
          {label: 'Metered Price'.upcase, compute: invoice['estimatedComputePrice'], memory: invoice['estimatedMemoryPrice'], storage: invoice['estimatedStoragePrice'], network: invoice['estimatedNetworkPrice'], license: invoice['estimatedLicensePrice'], extra: invoice['estimatedExtraPrice'], running: invoice['estimatedRunningPrice'], total: invoice['estimatedTotalPrice'], currency: invoice['estimatedCurrency']}
        ]
        if options[:show_costs] # && json_response['masterAccount'] != false
          cost_rows += [
            {label: 'Metered Cost'.upcase, compute: invoice['estimatedComputeCost'], memory: invoice['estimatedMemoryCost'], storage: invoice['estimatedStorageCost'], network: invoice['estimatedNetworkCost'], license: invoice['estimatedLicenseCost'], extra: invoice['estimatedExtraCost'], running: invoice['estimatedRunningCost'], total: invoice['estimatedTotalCost'], currency: invoice['estimatedCurrency']},
          ]
        end
      end
      cost_columns = {
        "" => lambda {|it| it[:label] },
        "Compute" => lambda {|it| format_money(it[:compute], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
        "Memory" => lambda {|it| format_money(it[:memory], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
        "Storage" => lambda {|it| format_money(it[:storage], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
        "Network" => lambda {|it| format_money(it[:network], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
        "License" => lambda {|it| format_money(it[:license], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
        "Extra" => lambda {|it| format_money(it[:extra], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
        "MTD" => lambda {|it| format_money(it[:running], it[:currency] || 'USD', {sigdig:options[:sigdig]}) },
        "Total" => lambda {|it| 
          format_money(it[:total], it[:currency] || 'USD', {sigdig:options[:sigdig]}) + ((it[:total].to_f > 0 && it[:total] != it[:running]) ? " (Projected)" : "")
        },
        "Currency" => lambda {|it| it[:currency] },
      }.upcase_keys!
      # remove columns that rarely have data...
      if cost_rows.sum { |it| it[:memory].to_f } == 0
        cost_columns.delete("Memory".upcase)
      end
      if cost_rows.sum { |it| it[:license].to_f } == 0
        cost_columns.delete("License".upcase)
      end
      if cost_rows.sum { |it| it[:extra].to_f } == 0
        cost_columns.delete("Extra".upcase)
      end
      print as_pretty_table(cost_rows, cost_columns, options)
      print reset,"\n"
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[invoice] [options]")
      opts.on('--tags LIST', String, "Tags in the format 'name:value, name:value'. This will add and remove tags.") do |val|
        options[:tags] = val
      end
      opts.on('--add-tags TAGS', String, "Add Tags in the format 'name:value, name:value'. This will only add/update tags.") do |val|
        options[:add_tags] = val
      end
      opts.on('--remove-tags TAGS', String, "Remove Tags in the format 'name, name:value'. This removes tags, the :value component is optional and must match if passed.") do |val|
        options[:remove_tags] = val
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an invoice.
[invoice] is required. This is the id of an invoice.
      EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    json_response = @invoices_interface.get(args[0])
    invoice = json_response['invoice']

    invoice_payload = parse_passed_options(options)
    if options[:tags]
      invoice_payload['tags'] = parse_metadata(options[:tags])
    end
    if options[:add_tags]
      invoice_payload['addTags'] = parse_metadata(options[:add_tags])
    end
    if options[:remove_tags]
      invoice_payload['removeTags'] = parse_metadata(options[:remove_tags])
    end

    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'invoice' => invoice_payload})
    else
      payload.deep_merge!({'invoice' => invoice_payload})
      if invoice_payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @invoices_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @invoices_interface.dry.update(invoice['id'], payload)
      return
    end
    json_response = @invoices_interface.update(invoice['id'], payload)
    invoice = json_response['invoice']
    render_response(json_response, options, 'invoice') do
      print_green_success "Updated invoice #{invoice['id']}"
      return _get(invoice["id"], {}, options)
    end
    return 0, nil
  end

  def refresh(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[-c CLOUD]")
      opts.on( '-c', '--clouds CLOUD', "Specify clouds to refresh costing for." ) do |val|
        payload[:clouds] ||= []
        payload[:clouds] << val
      end
      opts.on( '--all', "Refresh costing for all clouds. This can be used instead of --clouds" ) do
        payload[:all] = true
      end
      opts.on( '--date DATE', String, "Date to collect costing for. By default the cost data is collected for the end of the previous job interval (hour or day)." ) do |val|
        payload[:date] = val.to_s
      end
      build_standard_update_options(opts, options, [:query, :auto_confirm])
      opts.footer = <<-EOT
Refresh invoice costing data for the specified clouds.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    params.merge!(parse_query_options(options))
    if options[:payload]
      payload = options[:payload]
    end
    payload.deep_merge!(parse_passed_options(options))
    # --clouds lookup ID for name
    if payload[:clouds]
      cloud_ids = parse_cloud_id_list(payload[:clouds], {}, false, true)
      return 1, "clouds not found for #{payload[:clouds]}" if cloud_ids.nil?
      payload[:clouds] = cloud_ids
    end
    # are you sure?
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to refresh invoices?")
      return 9, "aborted command"
    end
    # ok, make the request
    @invoices_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @invoices_interface.dry.refresh(params, payload)
      return
    end
    json_response = @invoices_interface.refresh(params, payload)
    # render the result
    render_result = render_with_format(json_response, options)
    return 0 if render_result
    # print output
    print_green_success(json_response['msg'] || "Refreshing invoices")
    return 0
  end

  def list_line_items(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-a', '--all', "Display all details, costs and prices." ) do
        options[:show_actual_costs] = true
        options[:show_costs] = true
      end
      # opts.on('--actuals', '--actuals', "Display all actual costs: Compute, Memory, Storage, Network, Extra" ) do
      #   options[:show_actual_costs] = true
      # end
      opts.on('--costs', '--costs', "Display costs in addition to prices" ) do
        options[:show_costs] = true
      end
      opts.on('--invoice-id ID', String, "Filter by Invoice ID") do |val|
        params['invoiceId'] ||= []
        params['invoiceId'] << val
      end
      opts.on('--external-id ID', String, "Filter by External ID") do |val|
        params['externalId'] ||= []
        params['externalId'] << val
      end
      opts.on('-t', '--type TYPE', "Filter by Ref Type eg. ComputeSite (Group), ComputeZone (Cloud), ComputeServer (Host), Instance, Container, User") do |val|
        params['refType'] ||= []
        values = val.split(",").collect {|it| it.strip }.select {|it| it != "" }
        values.each { |it| params['refType'] << parse_invoice_ref_type(it) }
      end
      opts.on('--id ID', String, "Filter by Ref ID") do |val|
        ref_ids << val
      end
      opts.on('--ref-id ID', String, "Filter by Ref ID") do |val|
        ref_ids << val
      end
      opts.add_hidden_option('--ref-id')
      opts.on('--group ID', String, "Filter by Group") do |val|
        options[:groups] ||= []
        options[:groups] << val
      end
      opts.on( '-c', '--cloud CLOUD', "Filter by Cloud" ) do |val|
        options[:clouds] ||= []
        options[:clouds] << val
      end
      opts.on('--instance ID', String, "Filter by Instance") do |val|
        options[:instances] ||= []
        options[:instances] << val
      end
      opts.on('--container ID', String, "Filter by Container") do |val|
        params['containerId'] ||= []
        params['containerId'] << val
      end
      opts.on('--server ID', String, "Filter by Server (Host)") do |val|
        options[:servers] ||= []
        options[:servers] << val
      end
      opts.on('--user ID', String, "Filter by User") do |val|
        options[:users] ||= []
        options[:users] << val
      end
      opts.on('--project PROJECT', String, "View invoices for a project.") do |val|
        options[:projects] ||= []
        options[:projects] << val
      end
      # opts.on('--cluster ID', String, "Filter by Cluster") do |val|
      #   params['clusterId'] ||= []
      #   params['clusterId'] << val
      # end
      opts.on('--start DATE', String, "Start date in the format YYYY-MM-DD.") do |val|
        params['startDate'] = val #parse_time(val).utc.iso8601
      end
      opts.on('--end DATE', String, "End date in the format YYYY-MM-DD. Default is now.") do |val|
        params['endDate'] = val #parse_time(val).utc.iso8601
      end
      opts.on('--period PERIOD', String, "Period in the format YYYYMM. This can be used instead of start/end.") do |val|
        params['period'] = parse_period(val)
      end
      opts.on('--active [true|false]',String, "Filter by active.") do |val|
        params['active'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--estimate [true|false]',String, "Filter by estimate.") do |val|
        params['estimate'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      opts.on('--tenant ID', String, "View invoice line items for a tenant. Default is your own account.") do |val|
        params['accountId'] = val
      end
      opts.on('--tags Name=Value',String, "Filter by tags.") do |val|
        val.split(",").each do |value_pair|
          k,v = value_pair.strip.split("=")
          options[:tags] ||= {}
          options[:tags][k] ||= []
          options[:tags][k] << (v || '')
        end
      end
      opts.on('--totals', "View total costs and prices for all the invoices found.") do |val|
        params['includeTotals'] = true
        options[:show_invoice_totals] = true
      end
      opts.on('--totals-only', "View totals only") do |val|
        params['includeTotals'] = true
        options[:show_invoice_totals] = true
        options[:totals_only] = true
      end
      opts.on('--sigdig DIGITS', "Significant digits when rounding cost values for display as currency. Default is 2. eg. $3.50") do |val|
        options[:sigdig] = val.to_i
      end
      build_standard_list_options(opts, options)
      opts.footer = "List invoice line items."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    
    # construct params
    params.merge!(parse_list_options(options))
    if options[:clouds]
      cloud_ids = parse_cloud_id_list(options[:clouds], {}, false, true)
      return 1, "clouds not found for #{options[:clouds]}" if cloud_ids.nil?
      params['zoneId'] = cloud_ids
    end
    if options[:groups]
      group_ids = parse_group_id_list(options[:groups], {}, false, true)
      return 1, "groups not found for #{options[:groups]}" if group_ids.nil?
      params['siteId'] = group_ids
    end
    if options[:instances]
      instance_ids = parse_instance_id_list(options[:instances], {}, false, true)
      return 1, "instances not found for #{options[:instances]}" if instance_ids.nil?
      params['instanceId'] = instance_ids
    end
    if options[:servers]
      server_ids = parse_server_id_list(options[:servers], {}, false, true)
      return 1, "servers not found for #{options[:servers]}" if server_ids.nil?
      params['serverId'] = server_ids
    end
    if options[:users]
      user_ids = parse_user_id_list(options[:users], {}, false, true)
      return 1, "users not found for #{options[:users]}" if user_ids.nil?
      params['userId'] = user_ids
    end
    if options[:projects]
      project_ids = parse_project_id_list(options[:projects], {}, false, true)
      return 1, "projects not found for #{options[:projects]}" if project_ids.nil?
      params['projectId'] = project_ids
    end
    params['refId'] = ref_ids unless ref_ids.empty?
    if options[:tags] && !options[:tags].empty?
      options[:tags].each do |k,v|
        params['tags.' + k] = v
      end
    end
    @invoice_line_items_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @invoice_line_items_interface.dry.list(params)
      return
    end
    json_response = @invoice_line_items_interface.list(params)
    line_items = json_response['lineItems']
    render_response(json_response, options, 'lineItems') do
      title = "Morpheus Line Items"
      subtitles = []
      if params['startDate']
        subtitles << "Start Date: #{params['startDate']}"
      end
      if params['endDate']
        subtitles << "End Date: #{params['endDate']}"
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if line_items.empty?
        print yellow,"No line items found.",reset,"\n"
      else
        # current_date = Time.now
        # current_period = "#{current_date.year}#{current_date.month.to_s.rjust(2, '0')}"
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"INVOICE ID" => lambda {|it| it['invoiceId'] } },
          {"TYPE" => lambda {|it| format_invoice_ref_type(it) } },
          {"REF ID" => lambda {|it| it['refId'] } },
          {"REF NAME" => lambda {|it| it['refName'] } },
          #{"REF CATEGORY" => lambda {|it| it['refCategory'] } },
          {"START" => lambda {|it| format_date(it['startDate']) } },
          {"END" => lambda {|it| format_date(it['endDate']) } },
          {"USAGE TYPE" => lambda {|it| it['usageType'] } },
          {"USAGE CATEGORY" => lambda {|it| it['usageCategory'] } },
          {"USAGE" => lambda {|it| it['itemUsage'] } },
          {"RATE" => lambda {|it| it['itemRate'] } },
          {"UNIT" => lambda {|it| it['rateUnit'] } },
          {"PRICE" => lambda {|it| format_money(it['itemPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
        ] + (options[:show_costs] ? [
          {"COST" => lambda {|it| format_money(it['itemCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          {"TAX" => lambda {|it| format_money(it['itemTax'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
        ] : []) + [
          {"ITEM ID" => lambda {|it| truncate_string_right(it['itemId'], 65) } },
          {"ITEM NAME" => lambda {|it| it['itemName'] } },
          {"ITEM TYPE" => lambda {|it| it['itemType'] } },
          {"ITEM DESCRIPTION" => lambda {|it| it['itemDescription'] } },
          {"PRODUCT CODE" => lambda {|it| it['productCode'] } },
          "CREATED" => lambda {|it| format_local_dt(it['dateCreated']) },
          "UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) }
        ]

        # if options[:show_invoice_totals]
        #   line_item_totals = json_response['lineItemTotals']
        #   if line_item_totals
        #     totals_row = line_item_totals.clone
        #     totals_row['id'] = 'TOTAL:'
        #     #totals_row['usageCategory'] = 'TOTAL:'
        #     line_items = line_items + [totals_row]
        #   end
        # end
        unless options[:totals_only]
          print as_pretty_table(line_items, columns, options)
          print_results_pagination(json_response, {:label => "line item", :n_label => "line items"})
        end

        if options[:show_invoice_totals]
          line_item_totals = json_response['lineItemTotals']
          if line_item_totals
            print_h2 "Line Item Totals" unless options[:totals_only]
            invoice_totals_columns = [
              {"Items" => lambda {|it| format_number(json_response['meta']['total']) rescue '' } },
              #{"Usage" => lambda {|it| it['itemUsage'] } },
              {"Price" => lambda {|it| format_money(it['itemPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
            ] + (options[:show_costs] ? [
              {"Cost" => lambda {|it| format_money(it['itemCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
              #{"Tax" => lambda {|it| format_money(it['itemTax'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) } },
          
            ] : [])
            print_description_list(invoice_totals_columns, line_item_totals)
          else
            print "\n"
            print yellow, "No line item totals data", reset, "\n"
          end
        end

      end
      print reset,"\n"
    end
    if line_items.empty?
      return 1, "no line items found"
    else
      return 0, nil
    end
  end
  
  def get_line_item(args)
    options, params = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('--sigdig DIGITS', "Significant digits when rounding cost values for display as currency. Default is 2. eg. $3.50") do |val|
        options[:sigdig] = val.to_i
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific invoice line item.
[id] is required. This is the id of an invoice line item.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get_line_item(arg, params, options)
    end
  end


  def _get_line_item(id, params, options)
    @invoice_line_items_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @invoice_line_items_interface.dry.get(id, params)
      return
    end
    json_response = @invoice_line_items_interface.get(id, params)
    line_item = json_response['lineItem']
    render_response(json_response, options, 'lineItem') do
      print_h1 "Line Item Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Invoice ID" => lambda {|it| it['invoiceId'] },
        "Type" => lambda {|it| format_invoice_ref_type(it) },
        "Ref ID" => lambda {|it| it['refId'] },
        "Ref Name" => lambda {|it| it['refName'] },
        "Start" => lambda {|it| format_date(it['startDate']) },
        "End" => lambda {|it| it['endDate'] ? format_date(it['endDate']) : '' },
        "Usage Type" => lambda {|it| it['usageType'] },
        "Usage Category" => lambda {|it| it['usageCategory'] },
        "Item Usage" => lambda {|it| it['itemUsage'] },
        "Item Rate" => lambda {|it| it['itemRate'] },
        "Item Cost" => lambda {|it| format_money(it['itemCost'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) },
        "Item Price" => lambda {|it| format_money(it['itemPrice'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) },
        #"Item Tax" => lambda {|it| format_money(it['itemTax'], it['currency'] || 'USD', {sigdig:options[:sigdig]}) },
        #"Tax Type" => lambda {|it| it['taxType'] },
        "Item Term" => lambda {|it| it['itemTerm'] },
        "Item ID" => lambda {|it| it['itemId'] },
        "Item Name" => lambda {|it| it['itemName'] },
        "Item Type" => lambda {|it| it['itemType'] },
        "Item Description" => lambda {|it| it['itemDescription'] },
        "Product Code" => lambda {|it| it['productCode'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, line_item, options)
      
      print reset,"\n"
    end
    return 0, nil
  end

  private

  def invoice_object_key
    'invoice'
  end

  def invoice_list_key
    'invoices'
  end

  def invoice_line_item_object_key
    'lineItem'
  end

  def invoice_line_item_list_key
    'lineItems'
  end

  # def find_invoice_by_name_or_id(val)
  #   if val.to_s =~ /\A\d{1,}\Z/
  #     return find_invoice_by_id(val)
  #   else
  #     return find_invoice_by_name(val)
  #   end
  # end

  def find_invoice_by_id(id)
    begin
      json_response = @invoices_interface.get(id.to_i)
      return json_response['invoice']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Invoice not found by id #{id}"
      else
        raise e
      end
    end
  end

  # def find_invoice_by_name(name)
  #   invoices = @invoices_interface.list({name: name.to_s})['invoices']
  #   if invoices.empty?
  #     print_red_alert "Invoice not found by name #{name}"
  #     return nil
  #   elsif invoices.size > 1
  #     print_red_alert "#{invoices.size} invoices found by name #{name}"
  #     print_invoices_table(invoices, {color: red})
  #     print_red_alert "Try using ID instead"
  #     print reset,"\n"
  #     return nil
  #   else
  #     return invoices[0]
  #   end
  # end

  def format_invoice_ref_type(it)
    if it['refType'] == 'ComputeZone'
      "Cloud"
    # elsif it['refType'] == 'ComputeServer'
    #   "Host"
    elsif it['refType'] == 'ComputeServerGroup'
      "Cluster"
    elsif it['refType'] == 'ComputeSite'
      "Group"
    else
      it['refType']
    end
  end

  def parse_invoice_ref_type(ref_type)
    val = ref_type.to_s.downcase
    if val == 'cloud' || val == 'zone'
      'ComputeZone'
    elsif val == 'instance'
      'Instance'
    elsif val == 'server' || val == 'host'
      'ComputeServer'
    elsif val == 'cluster'
      'ComputeServerGroup'
    elsif val == 'group' || val == 'site'
      'ComputeSite'
    elsif val == 'user'
      'User'
    else
      ref_type
    end
  end

  # convert "202003" to "March 2020"
  def format_invoice_period(it)
    interval = it['interval']
    period = it['period']
    if period
      if interval == 'month'
        year = period[0..3]
        month = period[4..5]
        if year && month
          month_name = Date::MONTHNAMES[month.to_i] || "#{month}?"
          return "#{month_name} #{year}"
        else
          return "#{year}"
        end
      else
        return it['period']
      end
    else
      return "n/a"
    end
  end

  # convert "March 2020" to "202003"
  def parse_period(period, interval='month')
    if period
      if interval == 'month'
        if period.include?(" ")
          period_parts = period.split(" ")
          month = Date::MONTHNAMES.index(period_parts[0])
          year = period_parts[1].to_i
          if month
            return "#{year}#{month.to_s.rjust(2, '0')}"
          else
            return "#{year}00" # meh, bad month name, raise error probably
          end
        else
          return "#{period}"
        end
      else
        return "#{period}"
      end
    else
      return nil
    end
  end
  
  def get_current_period()
    now = Time.now.utc
    now.year.to_s + now.month.to_s.rjust(2,'0')
  end

  def format_server_power_state(server, return_color=cyan)
    out = ""
    if server['powerState'] == 'on'
      out << "#{green}ON#{return_color}"
    elsif server['powerState'] == 'off'
      out << "#{red}OFF#{return_color}"
    else
      out << "#{white}#{server['powerState'].to_s.upcase}#{return_color}"
    end
    out
  end

end
