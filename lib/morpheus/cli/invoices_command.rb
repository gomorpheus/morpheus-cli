require 'morpheus/cli/cli_command'
require 'date'

class Morpheus::Cli::InvoicesCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'invoices'

  register_subcommands :list, :get
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @invoices_interface = @api_client.invoices
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
        options[:show_actual_costs] = true
        options[:show_costs] = true
        options[:show_prices] = true
        options[:show_raw_data] = true
      end
      opts.on('--actuals', '--actuals', "Display all actual costs: Compute, Memory, Storage, etc." ) do
        options[:show_actual_costs] = true
      end
      opts.on('--costs', '--costs', "Display all costs: Compute, Memory, Storage, etc." ) do
        options[:show_costs] = true
      end
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
        params['siteId'] ||= []
        params['siteId'] << val
      end
      opts.on('--cloud ID', String, "Filter by Cloud") do |val|
        params['zoneId'] ||= []
        params['zoneId'] << val
      end
      opts.on('--instance ID', String, "Filter by Instance") do |val|
        params['instanceId'] ||= []
        params['instanceId'] << val
      end
      opts.on('--container ID', String, "Filter by Container") do |val|
        params['containerId'] ||= []
        params['containerId'] << val
      end
      opts.on('--server ID', String, "Filter by Server (Host)") do |val|
        params['serverId'] ||= []
        params['serverId'] << val
      end
      opts.on('--user ID', String, "Filter by User") do |val|
        params['userId'] ||= []
        params['userId'] << val
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
      build_standard_list_options(opts, options)
      opts.footer = "List invoices."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
      return 1
    end
    begin
      params['rawData'] = true if options[:show_raw_data]
      params['refId'] = ref_ids unless ref_ids.empty?
      params.merge!(parse_list_options(options))
      @invoices_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @invoices_interface.dry.list(params)
        return
      end
      json_response = @invoices_interface.list(params)
      render_result = render_with_format(json_response, options, 'invoices')
      return 0 if render_result
      invoices = json_response['invoices']
      title = "Morpheus Invoices"
      subtitles = []
      if params['status']
        subtitles << "Status: #{params['status']}"
      end
      if params['alarmStatus'] == 'acknowledged'
        subtitles << "(Acknowledged)"
      end
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
        columns = [
          {"INVOICE ID" => lambda {|it| it['id'] } },
          {"TYPE" => lambda {|it| format_invoice_ref_type(it) } },
          {"REF ID" => lambda {|it| it['refId'] } },
          {"REF NAME" => lambda {|it| it['refName'] } },
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

            if it['runningMultiplier'] && it['runningMultiplier'].to_i != 1 && it['totalCost'].to_f > 0
              format_money(it['totalCost']) + " (Projected)"
            else
              format_money(it['totalCost'])
            end
          } },
          {"ACTUAL MTD" => lambda {|it| format_money(it['actualRunningCost']) } },
          {"ACTUAL TOTAL" => lambda {|it| 
            if it['runningMultiplier'] && it['runningMultiplier'].to_i != 1 && it['actualTotalCost'].to_f > 0
              format_money(it['actualTotalCost']) + " (Projected)"
            else
              format_money(it['actualTotalCost'])
            end
          } }
        ]
        if options[:show_costs]
          columns += [
            {"COMPUTE" => lambda {|it| format_money(it['computeCost']) } },
            # {"MEMORY" => lambda {|it| format_money(it['memoryCost']) } },
            {"STORAGE" => lambda {|it| format_money(it['storageCost']) } },
            {"NETWORK" => lambda {|it| format_money(it['networkCost']) } },
            {"OTHER" => lambda {|it| format_money(it['extraCost']) } },
          ]
        end
        if options[:show_actual_costs]
          columns += [
            {"ACTUAL COMPUTE" => lambda {|it| format_money(it['actualComputePrice']) } },
            # {"ACTUAL MEMORY" => lambda {|it| format_money(it['actualMemoryPrice']) } },
            {"ACTUAL STORAGE" => lambda {|it| format_money(it['actualStoragePrice']) } },
            {"ACTUAL NETWORK" => lambda {|it| format_money(it['actualNetworkPrice']) } },
            {"ACTUAL OTHER" => lambda {|it| format_money(it['actualExtraPrice']) } },
          ]
        end

        if options[:show_prices]
          columns += [
            {"COMPUTE PRICE" => lambda {|it| format_money(it['computePrice']) } },
            # {"MEMORY PRICE" => lambda {|it| format_money(it['memoryPrice']) } },
            {"STORAGE PRICE" => lambda {|it| format_money(it['storagePrice']) } },
            {"NETWORK PRICE" => lambda {|it| format_money(it['networkPrice']) } },
            {"OTHER PRICE" => lambda {|it| format_money(it['extraPrice']) } },
            {"MTD PRICE" => lambda {|it| format_money(it['runningPrice']) } },
            {"TOTAL PRICE" => lambda {|it| 
              if it['runningMultiplier'] && it['runningMultiplier'].to_i != 1 && it['totalPrice'].to_f > 0
                format_money(it['totalPrice']) + " (Projected)"
              else
                format_money(it['totalPrice'])
              end
            } }
          ]
        end

        if options[:show_raw_data]
          columns += [{"RAW DATA" => lambda {|it| truncate_string(it['rawData'].to_s, 10) } }]
        end
        print as_pretty_table(invoices, columns, options)
        print_results_pagination(json_response, {:label => "invoice", :n_label => "invoices"})
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
      opts.banner = subcommand_usage("[id]")
      opts.on('--raw-data', '--raw-data', "Display Raw Data, the cost data from the cloud provider's API.") do |val|
        options[:show_raw_data] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = "Get details about a specific invoice."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
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
        "Power State" => lambda {|it| format_server_power_state(it) },
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Period" => lambda {|it| format_invoice_period(it) },
        #"Interval" => lambda {|it| it['interval'] },
        "Start" => lambda {|it| format_date(it['startDate']) },
        "End" => lambda {|it| it['endDate'] ? format_date(it['endDate']) : '' },
        "Estimate" => lambda {|it| format_boolean(it['estimate']) },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      # remove columns that do not apply
      if !invoice['plan']
        description_cols.delete("Plan")
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
        {label: 'Usage Price'.upcase, compute: invoice['computePrice'], memory: invoice['memoryPrice'], storage: invoice['storagePrice'], network: invoice['networkPrice'], license: invoice['licensePrice'], extra: invoice['extraPrice'], running: invoice['runningPrice'], total: invoice['totalPrice']},
        {label: 'Usage Cost'.upcase, compute: invoice['computeCost'], memory: invoice['memoryCost'], storage: invoice['storageCost'], network: invoice['networkCost'], license: invoice['licenseCost'], extra: invoice['extraCost'], running: invoice['runningCost'], total: invoice['totalCost']},
        {label: 'Actual Cost'.upcase, compute: invoice['actualComputeCost'], memory: invoice['actualMemoryCost'], storage: invoice['actualStorageCost'], network: invoice['actualNetworkCost'], license: invoice['actualLicenseCost'], extra: invoice['actualExtraCost'], running: invoice['actualRunningCost'], total: invoice['actualTotalCost']},
      ]
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
          if invoice['runningMultiplier'] && invoice['runningMultiplier'].to_i != 1 && it[:total].to_f.to_f > 0
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
        puts invoice['rawData']
      end
      

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
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
    elsif it['refType'] == 'Instance'
      "Instance"
    elsif it['refType'] == 'ComputeServer'
      "Host"
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
