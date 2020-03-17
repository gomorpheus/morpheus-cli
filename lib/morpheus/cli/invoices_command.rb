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
      opts.on('--type TYPE', String, "Find invoices for a Ref Type eg. ComputeSite (Group), ComputeZone (Cloud), ComputeServer (Host), Instance, Container, User") do |val|
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
      opts.on('--ref-id ID', String, "Find invoices for a Ref ID") do |val|
        ref_ids << val
      end
      opts.on('--group ID', String, "Find invoices for a Group") do |val|
        # params['siteId'] = val
        params['refType'] = 'ComputeSite'
        ref_ids << val
      end
      opts.on('--cloud ID', String, "Find invoices for a Cloud") do |val|
        # params['zoneId'] = val
        params['refType'] = 'ComputeZone'
        ref_ids << val
      end
      opts.on('--instance ID', String, "Find invoices for an Instance") do |val|
        # params['instanceId'] = val
        params['refType'] = 'Instance'
        ref_ids << val
      end
      opts.on('--container ID', String, "Find invoices for a Container") do |val|
        # params['instanceId'] = val
        params['refType'] = 'Container'
        ref_ids << val
      end
      opts.on('--server ID', String, "Find invoices for a Server (Host)") do |val|
        # params['serverId'] = val
        params['refType'] = 'ComputeServer'
        ref_ids << val
      end
      opts.on('--user ID', String, "Find invoices for a User") do |val|
        # params['userId'] = val
        params['refType'] = 'User'
        ref_ids << val
      end
      # opts.on('--cluster ID', String, "Filter by Cluster") do |val|
      #   # params['clusterId'] = val
      #   params['refType'] = 'ComputeServerGroup'
      #   params['refId'] = val.to_i
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
      opts.on('--tenant ID', String, "View invoices for a tenant. Default is your own account.") do |val|
        params['accountId'] = val
      end
      opts.on('--raw-data', '--raw-data', "Display Raw Data, the cost data from the cloud provider's API.") do |val|
        options[:show_raw_data] = true
        params['rawData'] = true
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
      params['refId'] = ref_ids unless ref_ids.empty?
      params.merge!(parse_list_options(options))
      @invoices_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @invoices_interface.dry.list(params)
        return
      end
      json_response = @invoices_interface.list(params)
      render_result = render_with_format(json_response, options, 'invoice')
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
        columns = [
          {"INVOICE ID" => lambda {|it| it['id'] } },
          {"TYPE" => lambda {|it| format_invoice_ref_type(it) } },
          {"REF ID" => lambda {|it| it['refId'] } },
          {"REF NAME" => lambda {|it| it['refName'] } },
          #{"INTERVAL" => lambda {|it| it['interval'] } },
          {"ACCOUNT" => lambda {|it| it['account'] ? it['account']['name'] : '' } },
          {"ACTIVE" => lambda {|it| format_boolean(it['active']) } },
          {"PERIOD" => lambda {|it| format_invoice_period(it) } },
          {"START" => lambda {|it| format_local_dt(it['startDate']) } },
          {"END" => lambda {|it| it['endDate'] ? format_local_dt(it['endDate']) : '' } },
          {"PRICE" => lambda {|it| format_money(it['totalPrice']) } },
          {"COST" => lambda {|it| format_money(it['totalCost']) } },
        ]
        if options[:show_raw_data]
          columns << {"RAW DATA" => lambda {|it| truncate_string(it['rawData'].to_s, 10) } }
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
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Period" => lambda {|it| format_invoice_period(it) },
        #"Interval" => lambda {|it| it['interval'] },
        "Start" => lambda {|it| format_local_dt(it['startDate']) },
        "End" => lambda {|it| it['endDate'] ? format_local_dt(it['endDate']) : '' },
        "Estimate" => lambda {|it| format_boolean(it['estimate']) },
        "Price" => lambda {|it| format_money(it['totalPrice']) },
        "Cost" => lambda {|it| format_money(it['totalCost']) },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, invoice)

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

end
