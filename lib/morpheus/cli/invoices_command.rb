require 'morpheus/cli/cli_command'
require 'date'

class Morpheus::Cli::InvoicesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'invoices'

  register_subcommands :list, :get, :refresh,
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
      opts.on('-a', '--all', "Display all costs, prices and raw data" ) do
        options[:show_estimates] = true
        # options[:show_costs] = true
        options[:show_prices] = true
        options[:show_raw_data] = true
      end
      opts.on('--estimates', '--estimates', "Display all estimated costs, from usage info: Compute, Memory, Storage, etc." ) do
        options[:show_estimates] = true
      end
      # opts.on('--costs', '--costs', "Display all costs: Compute, Memory, Storage, etc." ) do
      #   options[:show_costs] = true
      # end
      opts.on('--prices', '--prices', "Display prices: Total, Compute, Memory, Storage, etc." ) do
        options[:show_prices] = true
      end
      opts.on('--type TYPE', String, "Filter by Ref Type eg. ComputeSite (Group), ComputeZone (Cloud), ComputeServer (Host), Instance, Container, User") do |val|
        if val.to_s.downcase == 'cloud' || val.to_s.downcase == 'zone'
          params['refType'] = 'ComputeZone'
        elsif val.to_s.downcase == 'instance'
          params['refType'] = 'Instance'
        elsif val.to_s.downcase == 'server' || val.to_s.downcase == 'host'
          params['refType'] = 'ComputeServer'
        elsif val.to_s.downcase == 'cluster'
          params['refType'] = 'ComputeServerGroup'
        elsif val.to_s.downcase == 'group'
          params['refType'] = 'ComputeSite'
        elsif val.to_s.downcase == 'user'
          params['refType'] = 'User'
        else
          params['refType'] = val
        end
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
      opts.on('--raw-data', '--raw-data', "Display Raw Data, the cost data from the cloud provider's API.") do |val|
        options[:show_raw_data] = true
      end
      opts.on('--totals', "View total costs and prices for all the invoices found.") do |val|
        params['includeTotals'] = true
        options[:show_invoice_totals] = true
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
      cloud_ids = parse_cloud_id_list(options[:clouds])
      return 1, "clouds not found for #{options[:clouds]}" if cloud_ids.nil?
      params['zoneId'] = cloud_ids
    end
    if options[:groups]
      group_ids = parse_group_id_list(options[:groups])
      return 1, "groups not found for #{options[:groups]}" if group_ids.nil?
      params['siteId'] = group_ids
    end
    if options[:instances]
      instance_ids = parse_instance_id_list(options[:instances])
      return 1, "instances not found for #{options[:instances]}" if instance_ids.nil?
      params['instanceId'] = instance_ids
    end
    if options[:servers]
      server_ids = parse_server_id_list(options[:servers])
      return 1, "servers not found for #{options[:servers]}" if server_ids.nil?
      params['serverId'] = server_ids
    end
    if options[:users]
      user_ids = parse_user_id_list(options[:users])
      return 1, "users not found for #{options[:users]}" if user_ids.nil?
      params['userId'] = user_ids
    end
    if options[:projects]
      project_ids = parse_project_id_list(options[:projects])
      return 1, "projects not found for #{options[:projects]}" if project_ids.nil?
      params['projectId'] = project_ids
    end
    params['rawData'] = true if options[:show_raw_data]
    params['refId'] = ref_ids unless ref_ids.empty?
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
      else
        # current_date = Time.now
        # current_period = "#{current_date.year}#{current_date.month.to_s.rjust(2, '0')}"
        show_projects = invoices.find {|it| it['project'] } || (params['projectId'] || params['projectName'] || params['projectTag'])
        columns = [
          {"INVOICE ID" => lambda {|it| it['id'] } },
          {"TYPE" => lambda {|it| format_invoice_ref_type(it) } },
          {"REF ID" => lambda {|it| it['refId'] } },
          {"REF NAME" => lambda {|it| it['refName'] } }
        ] + (show_projects ? [
          {"PROJECT ID" => lambda {|it| it['project'] ? it['project']['id'] : '' } },
          {"PROJECT NAME" => lambda {|it| it['project'] ? it['project']['name'] : '' } },
          {"PROJECT TAGS" => lambda {|it| it['project'] ? truncate_string(format_metadata(it['project']['tags']), 50) : '' } }
        ] : []) + [
          #{"INTERVAL" => lambda {|it| it['interval'] } },
          {"CLOUD" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' } },
          {"ACCOUNT" => lambda {|it| it['account'] ? it['account']['name'] : '' } },
          {"ACTIVE" => lambda {|it| format_boolean(it['active']) } },
          #{"ESTIMATE" => lambda {|it| format_boolean(it['estimate']) } },
          {"PERIOD" => lambda {|it| format_invoice_period(it) } },
          {"START" => lambda {|it| format_date(it['startDate']) } },
          {"END" => lambda {|it| it['endDate'] ? format_date(it['endDate']) : '' } },
          {"MTD" => lambda {|it| format_money(it['runningCost']) } },
          {"TOTAL" => lambda {|it| 
            if it['runningMultiplier'] && it['runningMultiplier'].to_i != 1 && it['totalCost'].to_f > 0 && get_current_period == it['period']
              format_money(it['totalCost']) + " (Projected)"
            else
              format_money(it['totalCost'])
            end
          } }
        ]
        
        columns += [
          {"COMPUTE" => lambda {|it| format_money(it['computeCost']) } },
          # {"MEMORY" => lambda {|it| format_money(it['memoryCost']) } },
          {"STORAGE" => lambda {|it| format_money(it['storageCost']) } },
          {"NETWORK" => lambda {|it| format_money(it['networkCost']) } },
          {"OTHER" => lambda {|it| format_money(it['extraCost']) } },
        ]
        if options[:show_prices]
          columns += [
            {"COMPUTE PRICE" => lambda {|it| format_money(it['computePrice']) } },
            # {"MEMORY PRICE" => lambda {|it| format_money(it['memoryPrice']) } },
            {"STORAGE PRICE" => lambda {|it| format_money(it['storagePrice']) } },
            {"NETWORK PRICE" => lambda {|it| format_money(it['networkPrice']) } },
            {"OTHER PRICE" => lambda {|it| format_money(it['extraPrice']) } },
            {"MTD PRICE" => lambda {|it| format_money(it['runningPrice']) } },
            {"TOTAL PRICE" => lambda {|it| 
              if it['runningMultiplier'] && it['runningMultiplier'].to_i != 1 && it['totalPrice'].to_f > 0 && get_current_period == it['period']
                format_money(it['totalPrice']) + " (Projected)"
              else
                format_money(it['totalPrice'])
              end
            } }
          ]
        end
        if options[:show_estimates]
          columns += [
            {"MTD EST." => lambda {|it| format_money(it['estimatedRunningCost']) } },
            {"TOTAL EST." => lambda {|it| 
              if it['runningMultiplier'] && it['runningMultiplier'].to_i != 1 && it['estimatedTotalCost'].to_f > 0 && get_current_period == it['period']
                format_money(it['estimatedTotalCost']) + " (Projected)"
              else
                format_money(it['estimatedTotalCost'])
              end
            } },
            {"COMPUTE EST." => lambda {|it| format_money(it['estimatedComputeCost']) } },
            # {"MEMORY  EST." => lambda {|it| format_money(it['estimatedMemoryCost']) } },
            {"STORAGE EST." => lambda {|it| format_money(it['estimatedStorageCost']) } },
            {"NETWORK EST." => lambda {|it| format_money(it['estimatedNetworkCost']) } },
            {"OTHER EST." => lambda {|it| format_money(it['estimatedExtraCost']) } },
          ]
        end
        if options[:show_raw_data]
          columns += [{"RAW DATA" => lambda {|it| truncate_string(it['rawData'].to_s, 10) } }]
        end
        print as_pretty_table(invoices, columns, options)
        print_results_pagination(json_response, {:label => "invoice", :n_label => "invoices"})

        if options[:show_invoice_totals]
          invoice_totals = json_response['invoiceTotals']
          if invoice_totals
            print_h2 "Invoice Totals"
            invoice_totals_columns = {
              "# Invoices" => lambda {|it| format_number(json_response['meta']['total']) rescue '' },
              "Total Price" => lambda {|it| format_money(it['actualTotalPrice']) },
              "Total Cost" => lambda {|it| format_money(it['actualTotalCost']) },
              "Running Price" => lambda {|it| format_money(it['actualRunningPrice']) },
              "Running Cost" => lambda {|it| format_money(it['actualRunningCost']) },
              # "Invoice Total Price" => lambda {|it| format_money(it['invoiceTotalPrice']) },
              # "Invoice Total Cost" => lambda {|it| format_money(it['invoiceTotalCost']) },
              # "Invoice Running Price" => lambda {|it| format_money(it['invoiceRunningPrice']) },
              # "Invoice Running Cost" => lambda {|it| format_money(it['invoiceRunningCost']) },
              # "Estimated Total Price" => lambda {|it| format_money(it['estimatedTotalPrice']) },
              # "Estimated Total Cost" => lambda {|it| format_money(it['estimatedTotalCost']) },
              # "Compute Price" => lambda {|it| format_money(it['computePrice']) },
              # "Compute Cost" => lambda {|it| format_money(it['computeCost']) },
            }
            print_description_list(invoice_totals_columns, invoice_totals)
          else
            print "\n"
            print yellow, "No invoice totals data", reset, "\n"
          end
        end
      end
      print reset,"\n"
      return 0, nil
    end
  end
  
  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('-a', '--all', "Display all costs, prices and raw data" ) do
        options[:show_estimates] = true
        # options[:show_costs] = true
        options[:show_prices] = true
        options[:show_raw_data] = true
        options[:max_line_items] = 10000
      end
      opts.on('--estimates', '--estimates', "Display all estimated costs, from usage info: Compute, Memory, Storage, etc." ) do
        options[:show_estimates] = true
      end
      opts.on('--raw-data', '--raw-data', "Display Raw Data, the cost data from the cloud provider's API.") do |val|
        options[:show_raw_data] = true
      end
      opts.on('--pretty-raw-data', '--raw-data', "Display Raw Data that is a bit more pretty") do |val|
        options[:show_raw_data] = true
        options[:pretty_json] = true
      end
      opts.on('--no-line-items', '--no-line-items', "Do not display line items.") do |val|
        options[:hide_line_items] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a specific invoice."
      opts.footer = <<-EOT
Get details about a specific invoice.
[id] is required. This is the id of an invoice.
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

  def _get(id, options)
    params = {}
    if options[:show_raw_data]
      params['rawData'] = true
    end
    begin
      @invoices_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @invoices_interface.dry.get(id, params)
        return
      end
      json_response = @invoices_interface.get(id, params)
      invoice = json_response['invoice']
      render_result = render_with_format(json_response, options, 'invoice')
      return 0 if render_result

      print_h1 "Invoice Details"
      print cyan

      
      description_cols = {
        "Invoice ID" => lambda {|it| it['id'] },
        "Type" => lambda {|it| format_invoice_ref_type(it) },
        "Ref ID" => lambda {|it| it['refId'] },
        "Ref Name" => lambda {|it| it['refName'] },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Project ID" => lambda {|it| it['project'] ? it['project']['id'] : '' },
        "Project Name" => lambda {|it| it['project'] ? it['project']['name'] : '' },
        "Project Tags" => lambda {|it| it['project'] ? format_metadata(it['project']['tags']) : '' },
        "Power State" => lambda {|it| format_server_power_state(it) },
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Period" => lambda {|it| format_invoice_period(it) },
        "Estimate" => lambda {|it| format_boolean(it['estimate']) },
        #"Interval" => lambda {|it| it['interval'] },
        "Start" => lambda {|it| format_date(it['startDate']) },
        "End" => lambda {|it| it['endDate'] ? format_date(it['endDate']) : '' },
        "Ref Start" => lambda {|it| format_local_dt(it['refStart']) },
        "Ref End" => lambda {|it| it['refEnd'] ? format_local_dt(it['refEnd']) : '' },
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
      if !['ComputeServer','Instance','Container'].include?(invoice['refType'])
        description_cols.delete("Power State")
      end
      print_description_list(description_cols, invoice)
=begin
      print_h2 "Costs"
      cost_columns = {
        "Compute" => lambda {|it| format_money(it['computeCost']) },
        "Memory" => lambda {|it| format_money(it['memoryCost']) },
        "Storage" => lambda {|it| format_money(it['storageCost']) },
        "Network" => lambda {|it| format_money(it['networkCost']) },
        "License" => lambda {|it| format_money(it['licenseCost']) },
        "Other" => lambda {|it| format_money(it['extraCost']) },
        "Running" => lambda {|it| format_money(it['runningCost']) },
        "Total Cost" => lambda {|it| format_money(it['totalCost']) },
      }
      print as_pretty_table([invoice], cost_columns, options)

      print_h2 "Prices"
      price_columns = {
        "Compute" => lambda {|it| format_money(it['computePrice']) },
        "Memory" => lambda {|it| format_money(it['memoryPrice']) },
        "Storage" => lambda {|it| format_money(it['storagePrice']) },
        "Network" => lambda {|it| format_money(it['networkPrice']) },
        "License" => lambda {|it| format_money(it['licensePrice']) },
        "Other" => lambda {|it| format_money(it['extraPrice']) },
        "Running" => lambda {|it| format_money(it['runningPrice']) },
        "Total Price" => lambda {|it| format_money(it['totalPrice']) },
      }
      print as_pretty_table([invoice], price_columns, options)
=end
      
      # current_date = Time.now
      # current_period = "#{current_date.year}#{current_date.month.to_s.rjust(2, '0')}"

      print "\n"
      # print_h2 "Costs"
      cost_rows = [
        {label: 'Price'.upcase, compute: invoice['computePrice'], memory: invoice['memoryPrice'], storage: invoice['storagePrice'], network: invoice['networkPrice'], license: invoice['licensePrice'], extra: invoice['extraPrice'], running: invoice['runningPrice'], total: invoice['totalPrice']},
        {label: 'Cost'.upcase, compute: invoice['computeCost'], memory: invoice['memoryCost'], storage: invoice['storageCost'], network: invoice['networkCost'], license: invoice['licenseCost'], extra: invoice['extraCost'], running: invoice['runningCost'], total: invoice['totalCost']},
      ]
      if options[:show_estimates]
        cost_rows += [
          {label: 'Estimated Cost'.upcase, compute: invoice['estimatedComputeCost'], memory: invoice['estimatedMemoryCost'], storage: invoice['estimatedStorageCost'], network: invoice['estimatedNetworkCost'], license: invoice['estimatedLicenseCost'], extra: invoice['estimatedExtraCost'], running: invoice['estimatedRunningCost'], total: invoice['estimatedTotalCost']},
          {label: 'Estimated Price'.upcase, compute: invoice['estimatedComputeCost'], memory: invoice['estimatedMemoryCost'], storage: invoice['estimatedStorageCost'], network: invoice['estimatedNetworkCost'], license: invoice['estimatedLicenseCost'], extra: invoice['estimatedExtraCost'], running: invoice['estimatedRunningCost'], total: invoice['estimatedTotalCost']},
        ]
      end
      cost_columns = {
        "" => lambda {|it| it[:label] },
        "Compute".upcase => lambda {|it| format_money(it[:compute]) },
        "Memory".upcase => lambda {|it| format_money(it[:memory]) },
        "Storage".upcase => lambda {|it| format_money(it[:storage]) },
        "Network".upcase => lambda {|it| format_money(it[:network]) },
        "License".upcase => lambda {|it| format_money(it[:license]) },
        "Other".upcase => lambda {|it| format_money(it[:extra]) },
        "MTD" => lambda {|it| format_money(it[:running]) },
        "Total".upcase => lambda {|it| 
          if invoice['runningMultiplier'] && invoice['runningMultiplier'].to_i != 1 && it[:total].to_f.to_f > 0  && get_current_period == invoice['period']
            format_money(it[:total]) + " (Projected)"
          else
            format_money(it[:total])
          end
        },
      }
      # remove columns that rarely have data...
      if cost_rows.sum { |it| it[:memory].to_f } == 0
        cost_columns.delete("Memory".upcase)
      end
      if cost_rows.sum { |it| it[:license].to_f } == 0
        cost_columns.delete("License".upcase)
      end
      if cost_rows.sum { |it| it[:extra].to_f } == 0
        cost_columns.delete("Other".upcase)
      end
      print as_pretty_table(cost_rows, cost_columns, options)

      if options[:show_raw_data]
        print_h2 "Raw Data"
        puts as_json(invoice['rawData'], {pretty_json:false}.merge(options))
      end
      
      # Line Items
      line_items = invoice['lineItems']
      if line_items && line_items.size > 0 && options[:hide_line_items] != true

        line_items_columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"TYPE" => lambda {|it| format_invoice_ref_type(it) } },
          {"REF ID" => lambda {|it| it['refId'] } },
          {"REF NAME" => lambda {|it| it['refName'] } },
          #{"REF CATEGORY" => lambda {|it| it['refCategory'] } },
          {"START" => lambda {|it| format_date(it['startDate']) } },
          {"END" => lambda {|it| it['endDate'] ? format_date(it['endDate']) : '' } },
          {"USAGE TYPE" => lambda {|it| it['usageType'] } },
          {"USAGE CATEGORY" => lambda {|it| it['usageCategory'] } },
          {"USAGE" => lambda {|it| it['itemUsage'] } },
          {"RATE" => lambda {|it| it['itemRate'] } },
          {"COST" => lambda {|it| format_money(it['itemCost']) } },
          {"PRICE" => lambda {|it| format_money(it['itemPrice']) } },
          {"TAX" => lambda {|it| format_money(it['itemTax']) } },
          # {"TERM" => lambda {|it| it['itemTerm'] } },
          "CREATED" => lambda {|it| format_local_dt(it['dateCreated']) },
          "UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) }
        ]

        if options[:show_raw_data]
          line_items_columns += [{"RAW DATA" => lambda {|it| truncate_string(it['rawData'].to_s, 10) } }]
        end

        print_h2 "Line Items"
        #max_line_items = options[:max_line_items] ? options[:max_line_items].to_i : 5
        paged_line_items = line_items #.first(max_line_items)
        print as_pretty_table(paged_line_items, line_items_columns, options)
        print_results_pagination({total: line_items.size, size: paged_line_items.size}, {:label => "line item", :n_label => "line items"})
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def refresh(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[--daily] [--costing] [--current] [-c CLOUD]")
      opts.on( '--daily', "Refresh Daily Invoices" ) do
        payload[:daily] = true
      end
      opts.on( '--costing', "Refresh Costing Data" ) do
        payload[:costing] = true
      end
      opts.on( '--current', "Collect the most up to date costing data." ) do
        payload[:current] = true
      end
      opts.on( '--date DATE', String, "Date to collect costing for. By default the cost data is collected for the end of the previous period." ) do |val|
        payload[:date] = val.to_s
      end
      opts.on( '-c', '--cloud CLOUD', "Specify cloud(s) to refresh costing for." ) do |val|
        payload[:clouds] ||= []
        payload[:clouds] << val
      end
      opts.on( '--all', "Refresh costing for all clouds." ) do
        payload[:all] = true
      end
      # opts.on( '-f', '--force', "Force Refresh" ) do
      #   query_params[:force] = 'true'
      # end
      build_standard_update_options(opts, options, [:query, :auto_confirm])
      opts.footer = <<-EOT
Refresh invoices.
By default, nothing is changed.
Include --daily to regenerate invoice records.
Include --costing to refresh actual costing data.
Include --current to refresh costing data for the actual current time.
To get the latest invoice costing data, include --daily --costing --current --all 
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
    # --clouds
    if payload[:clouds]
      payload[:clouds] = parse_id_list(payload[:clouds]).collect {|cloud_id|
        if cloud_id.to_s =~ /\A\d{1,}\Z/
          cloud_id
        else
          cloud = find_cloud_option(cloud_id)
          return 1 if cloud.nil?
          cloud['id']
        end
      }
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
      opts.on('-a', '--all', "Display all costs, prices and raw data" ) do
        options[:show_actual_costs] = true
        options[:show_costs] = true
        options[:show_prices] = true
        options[:show_raw_data] = true
      end
      # opts.on('--actuals', '--actuals', "Display all actual costs: Compute, Memory, Storage, etc." ) do
      #   options[:show_actual_costs] = true
      # end
      # opts.on('--costs', '--costs', "Display all costs: Compute, Memory, Storage, etc." ) do
      #   options[:show_costs] = true
      # end
      # opts.on('--prices', '--prices', "Display prices: Total, Compute, Memory, Storage, etc." ) do
      #   options[:show_prices] = true
      # end
      opts.on('--invoice-id ID', String, "Filter by Invoice ID") do |val|
        params['invoiceId'] ||= []
        params['invoiceId'] << val
      end
      opts.on('--type TYPE', String, "Filter by Ref Type eg. ComputeSite (Group), ComputeZone (Cloud), ComputeServer (Host), Instance, Container, User") do |val|
        if val.to_s.downcase == 'cloud' || val.to_s.downcase == 'zone'
          params['refType'] = 'ComputeZone'
        elsif val.to_s.downcase == 'instance'
          params['refType'] = 'Instance'
        elsif val.to_s.downcase == 'server' || val.to_s.downcase == 'host'
          params['refType'] = 'ComputeServer'
        elsif val.to_s.downcase == 'cluster'
          params['refType'] = 'ComputeServerGroup'
        elsif val.to_s.downcase == 'group'
          params['refType'] = 'ComputeSite'
        elsif val.to_s.downcase == 'user'
          params['refType'] = 'User'
        else
          params['refType'] = val
        end
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
      opts.on('--raw-data', '--raw-data', "Display Raw Data, the cost data from the cloud provider's API.") do |val|
        options[:show_raw_data] = true
      end
      opts.on('--totals', "View total costs and prices for all the invoices found.") do |val|
        params['includeTotals'] = true
        options[:show_invoice_totals] = true
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
      cloud_ids = parse_cloud_id_list(options[:clouds])
      return 1, "clouds not found for #{options[:clouds]}" if cloud_ids.nil?
      params['zoneId'] = cloud_ids
    end
    if options[:groups]
      group_ids = parse_group_id_list(options[:groups])
      return 1, "groups not found for #{options[:groups]}" if group_ids.nil?
      params['siteId'] = group_ids
    end
    if options[:instances]
      instance_ids = parse_instance_id_list(options[:instances])
      return 1, "instances not found for #{options[:instances]}" if instance_ids.nil?
      params['instanceId'] = instance_ids
    end
    if options[:servers]
      server_ids = parse_server_id_list(options[:servers])
      return 1, "servers not found for #{options[:servers]}" if server_ids.nil?
      params['serverId'] = server_ids
    end
    if options[:users]
      user_ids = parse_user_id_list(options[:users])
      return 1, "users not found for #{options[:users]}" if user_ids.nil?
      params['userId'] = user_ids
    end
    if options[:projects]
      project_ids = parse_project_id_list(options[:projects])
      return 1, "projects not found for #{options[:projects]}" if project_ids.nil?
      params['projectId'] = project_ids
    end
    params['rawData'] = true if options[:show_raw_data]
    params['refId'] = ref_ids unless ref_ids.empty?
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
          {"END" => lambda {|it| it['endDate'] ? format_date(it['endDate']) : '' } },
          {"USAGE TYPE" => lambda {|it| it['usageType'] } },
          {"USAGE CATEGORY" => lambda {|it| it['usageCategory'] } },
          {"USAGE" => lambda {|it| it['itemUsage'] } },
          {"RATE" => lambda {|it| it['itemRate'] } },
          {"COST" => lambda {|it| format_money(it['itemCost']) } },
          {"PRICE" => lambda {|it| format_money(it['itemPrice']) } },
          {"TAX" => lambda {|it| format_money(it['itemTax']) } },
          # {"TERM" => lambda {|it| it['itemTerm'] } },
          "CREATED" => lambda {|it| format_local_dt(it['dateCreated']) },
          "UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) }
        ]

        if options[:show_raw_data]
          columns += [{"RAW DATA" => lambda {|it| truncate_string(it['rawData'].to_s, 10) } }]
        end
        if options[:show_invoice_totals]
          line_item_totals = json_response['lineItemTotals']
          if line_item_totals
            totals_row = line_item_totals.clone
            totals_row['id'] = 'TOTAL:'
            #totals_row['usageCategory'] = 'TOTAL:'
            line_items = line_items + [totals_row]
          end
        end
        print as_pretty_table(line_items, columns, options)
        print_results_pagination(json_response, {:label => "line item", :n_label => "line items"})

        # if options[:show_invoice_totals]
        #   line_item_totals = json_response['lineItemTotals']
        #   if line_item_totals
        #     print_h2 "Line Items Totals"
        #     invoice_totals_columns = {
        #       "# Line Items" => lambda {|it| format_number(json_response['meta']['total']) rescue '' },
        #       "Cost" => lambda {|it| format_money(it['itemCost']) },
        #       "Price" => lambda {|it| format_money(it['itemPrice']) },
        #       "Tax" => lambda {|it| format_money(it['itemTax']) },
        #       "Usage" => lambda {|it| it['itemUsage'] },
        #     }
        #     print_description_list(invoice_totals_columns, line_item_totals)
        #   else
        #     print "\n"
        #     print yellow, "No line item totals data", reset, "\n"
        #   end
        # end

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
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('--raw-data', '--raw-data', "Display Raw Data, the cost data from the cloud provider's API.") do |val|
        options[:show_raw_data] = true
      end
      opts.on('--pretty-raw-data', '--raw-data', "Display Raw Data that is a bit more pretty") do |val|
        options[:show_raw_data] = true
        options[:pretty_json] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a specific invoice line item."
      opts.footer = <<-EOT
Get details about a specific invoice line item.
[id] is required. This is the id of an invoice line item.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get_line_item(arg, options)
    end
  end

  def _get_line_item(id, options)
    params = {}
    if options[:show_raw_data]
      params['rawData'] = true
    end
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
        "Item Cost" => lambda {|it| format_money(it['itemCost']) },
        "Item Price" => lambda {|it| format_money(it['itemrPrice']) },
        "Item Tax" => lambda {|it| format_money(it['itemTax']) },
        "Item Term" => lambda {|it| it['itemTerm'] },
        #"Tax Type" => lambda {|it| it['taxType'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, line_item, options)
      
      if options[:show_raw_data]
        print_h2 "Raw Data"
        puts as_json(line_item['rawData'], {pretty_json:false}.merge(options))
      end

      print reset,"\n"
    end
    return 0, nil
  end

  private

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
