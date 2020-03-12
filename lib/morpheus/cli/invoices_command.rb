require 'morpheus/cli/cli_command'

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
    start_date, end_date = nil, nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      # opts.on('--group ID', String, "Filter by Group ID") do |val|
      #   params['siteId'] = val
      # end
      opts.on('--cloud ID', String, "Filter by Cloud ID") do |val|
        params['zoneId'] = val
      end
      opts.on('--instance ID', String, "Filter by Instance") do |val|
        params['instanceId'] = val
      end
      opts.on('--server ID', String, "Filter by Server (Host)") do |val|
        params['serverId'] = val
      end
      opts.on('--cluster ID', String, "Filter by Cluster") do |val|
        params['clusterId'] = val
      end
      opts.on('--start DATE', String, "Start date. Default is 3 months ago.") do |val|
        params['startDate'] = parse_time(val).utc.iso8601
      end
      opts.on('--end DATE', String, "End date. Default is now.") do |val|
        params['endDate'] = parse_time(val).utc.iso8601
      end
      opts.on('--active [true|false]',String, "Filter by active.") do |val|
        params['active'] = (val.to_s != 'false' && val.to_s != 'off')
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
      params['startDate'] = start_date.utc.iso8601 if start_date
      params['endDate'] = end_date.utc.iso8601 if end_date
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
        print_invoices_table(invoices, options)
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

    begin
      @invoices_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @invoices_interface.dry.get(id)
        return
      end
      json_response = @invoices_interface.get(id)
      invoice = json_response['invoice']
      render_result = render_with_format(json_response, options, 'invoice')
      return 0 if render_result

      print_h1 "Invoice Details"
      print cyan

      
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Type" => lambda {|it| format_invoice_ref_type(it) },
        "Ref ID" => lambda {|it| it['refId'] },
        "Ref Name" => lambda {|it| it['refName'] },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Period" => lambda {|it| it['period'] },
        "Interval" => lambda {|it| it['interval'] },
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Start" => lambda {|it| format_local_dt(it['startDate']) },
        "End" => lambda {|it| it['endDate'] ? format_local_dt(it['endDate']) : '' },
        "Estimate" => lambda {|it| format_boolean(it['estimate']) },
        "Price" => lambda {|it| format_money(it['totalPrice']) },
        "Cost" => lambda {|it| format_money(it['totalCost']) },
        "Actual Price" => lambda {|it| format_money(it['actualTotalPrice']) },
        "Actual Cost" => lambda {|it| format_money(it['actualTotalCost']) },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, invoice)

      if invoice['rawData'] && !invoice['rawData'].empty?
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

  def print_invoices_table(invoices, opts={})
    columns = [
      {"ID" => lambda {|it| it['id'] } },
      {"TYPE" => lambda {|it| format_invoice_ref_type(it) } },
      {"REF ID" => lambda {|it| it['refId'] } },
      {"REF NAME" => lambda {|it| it['refName'] } },
      {"PERIOD" => lambda {|it| it['period'] } },
      {"INTERVAL" => lambda {|it| it['interval'] } },
      {"ACCOUNT" => lambda {|it| it['account'] ? it['account']['name'] : '' } },
      {"ACTIVE" => lambda {|it| format_boolean(it['active']) } },
      {"START" => lambda {|it| format_local_dt(it['startDate']) } },
      {"END" => lambda {|it| it['endDate'] ? format_local_dt(it['endDate']) : '' } },
      {"PRICE" => lambda {|it| format_money(it['totalPrice']) } },
      {"COST" => lambda {|it| format_money(it['totalCost']) } },
      {"ACTUAL PRICE" => lambda {|it| format_money(it['actualTotalPrice']) } },
      {"ACTUAL COST" => lambda {|it| format_money(it['actualTotalCost']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(invoices, columns, opts)
  end

  def format_invoice_ref_type(it)
    if it['cloud']
      "Cloud"
    elsif it['instance']
      "Instance"
    elsif it['server']
      "Host"
    elsif it['cluster']
      "Cluster"
    elsif it['refType'] == 'ComputeSite'
      "Group"
    else
      it['refType']
    end
  end

  

end
