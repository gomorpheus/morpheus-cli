require 'morpheus/cli/cli_command'
require 'date'

class Morpheus::Cli::GuidanceCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'guidance'

  register_subcommands :list, :get, :stats, :execute, :ignore, :types
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @guidance_interface = @api_client.guidance
  end

  def handle(args)
    handle_subcommand(args)
  end

  def stats(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_get_options(opts, options)
      opts.footer = "Get guidance stats."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      @guidance_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @guidance_interface.dry.stats()
        return
      end
      json_response = @guidance_interface.stats()
      if options[:json]
        puts as_json(json_response, options, "stats")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "stats")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['stats']], options)
        return 0
      end

      stats = json_response['stats']

      print_h1 "Guidance Stats"
      print cyan
      description_cols = {
          "Total Actions" => lambda {|it| it['total'] },
          "Savings Available" => lambda {|it| format_money(it['savings']['amount'], it['savings']['currency'], {:minus_color => red}) }
      }
      print_description_list(description_cols, stats)

      print_h2 "Severity Totals"
      {'info'=>white, 'low'=>yellow, 'warning'=>bright_yellow, 'critical'=>red}.each do |level, color|
        print "#{cyan}#{level.capitalize}".rjust(14, ' ') + ": " + stats['severity'][level].to_s.ljust(10, ' ')
        # print "#{cyan} #{guidance['stats']['severity'][level]} of #{guidance['stats']['severity'].collect{|k, v| v}.reduce(:+)}".ljust(20, ' ')
        println generate_usage_bar(stats['severity'][level], stats['severity'].collect{|k, v| v}.reduce(:+), {:max_bars => 20, :bar_color => color})
      end

      # "size": 13, "shutdown": 15, "move": 0, "schedule"
      print_h2 "Action Totals"
      {'size'=>green, 'move'=>magenta, 'shutdown'=>red, 'schedule'=>bright_yellow}.each do |level, color|
        print "#{cyan}#{level.capitalize}".rjust(14, ' ') + ": " + stats['type'][level].to_s.ljust(10, ' ')
        println generate_usage_bar(stats['type'][level], stats['type'].collect{|k, v| v}.reduce(:+), {:max_bars => 20, :bar_color => color})
      end
      print reset "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_get_options(opts, options)
      opts.footer = "List discovery types."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
      return 1
    end

    begin
      @guidance_interface.setopts(options)

      if options[:dry_run]
        print_dry_run @guidance_interface.dry.types()
        return
      end
      json_response = @guidance_interface.types()
      if options[:json]
        puts as_json(json_response, options, "types")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "types")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['types']], options)
        return 0
      end

      types = json_response['types']

      print_h1 "Discovery Types"
      print cyan

      cols = [
          {"ID" => lambda {|it| it['id']}},
          {"NAME" => lambda {|it| it['name']}},
          {"TITLE" => lambda {|it| it['title']}},
          {"CODE" => lambda {|it| it['code']}}
      ];
      print as_pretty_table(types, cols, options)
      print reset "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-l', '--severity LEVEL', String, "Filter by Severity Level: info, low, warning, critical" ) do |val|
        params['severity'] = val
      end
      opts.on('-t', '--type TYPE', String, "Filter by Type") do |val|
        options[:type] = val
      end
      opts.on('-i', '--ignored', String, "Include Ignored Discoveries") do |val|
        params['state'] = 'ignored'
      end
      opts.on('-p', '--processed', String, "Include Executed Discoveries") do |val|
        params['state'] = 'processed'
      end
      opts.on('-a', '--any', String, "Include Executed and Ignored Discoveries") do |val|
        params['state'] = 'any'
      end
      build_standard_list_options(opts, options)
      opts.footer = "List discoveries"
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
      return 1
    end
    begin
      if options[:type]
        type = find_discovery_type(options[:type])

        if !type
          print_red_alert "Type #{options[:type]} not found"
          exit 1
        end
        params['code'] = type['code']
      end

      params.merge!(parse_list_options(options))
      @guidance_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @guidance_interface.dry.list(params)
        return
      end
      json_response = @guidance_interface.list(params)
      render_result = render_with_format(json_response, options, 'discoveries')
      return 0 if render_result

      discoveries = json_response['discoveries']

      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Discoveries", subtitles

      if discoveries.empty?
        print cyan,"No discoveries found.",reset,"\n"
      else
        cols = [
            {"ID" => lambda {|it| it['id']}},
            {"SEVERITY" => lambda {|it| (it['severity'] || '').capitalize}},
            {"TYPE/METRIC" => lambda {|it| it['type'] ? "#{it['type']['name']}: #{it['actionCategory'].capitalize || ''}" : ''}},
            {"ACTION" => lambda {|it| it['actionType'].capitalize}},
            {"CLOUD" => lambda {|it| it['zone'] ? it['zone']['name'] : ''}},
            {"RESOURCE" => lambda {|it| it['refName']}},
            {"SAVINGS" => lambda {|it| format_money(it['savings']['amount'], it['savings']['currency'], {:minus_color => red})}},
            {"DATE" => lambda {|it| format_local_date(it['dateCreated'], {:format => DEFAULT_TIME_FORMAT})}}
        ];
        if(params['state'] == 'any')
            cols << {'STATE' => lambda {|it| it['processed'] ? "#{green}Executed#{cyan}" : (it['ignored'] ? "#{yellow}Ignored#{cyan}" : '')}}
        end
        print as_pretty_table(discoveries, cols, options)
        print_results_pagination(json_response, {:label => "discovery", :n_label => "discoveries"})
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
      opts.footer = "Get details about a specific discovery."
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
    begin
      @guidance_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @guidance_interface.dry.get(id, params)
        return
      end
      json_response = @guidance_interface.get(id, params)
      discovery = json_response['discovery']
      render_result = render_with_format(json_response, options, 'discovery')
      return 0 if render_result

      print_h1 "Discovery Info"
      print cyan

      description_cols = {
          "ID" => lambda {|it| it['id']},
          #"Ref ID" => lambda {|it| it['refId'] },
          "Resource" => lambda {|it| it['refName'] },
          "Action" => lambda {|it| action_title(it['type'])},
          "Date" => lambda {|it| format_local_date(it['dateCreated'], {:format => DEFAULT_TIME_FORMAT})}
      }
      description_cols['Cloud'] = lambda {|it| it['zone']['name']} if discovery['refType'] == 'computeServer'
      description_cols.merge!({
          "Action Category" => lambda {|it| it['actionCategory'].capitalize},
          "Action Type" => lambda {|it| it['actionType'].capitalize},
          "Savings" => lambda {|it| format_money(it['savings']['amount'], it['savings']['currency']) + '/month'}
      })
      print_description_list(description_cols, discovery)

      if discovery['resource']
        print_h2 "Resource Info"

        if discovery['refType'] == 'computeServer'
          cols = [
              {"Power State" => lambda {|it| format_status(it['resource']['powerState'])}},
              {"Status" => lambda {|it| (format_status(it['resource']['status']))}},
              {"Type" => lambda {|it| it['resource']['computeServerType']['name']}},
              {"Platform" => lambda {|it| ((it['resource']['serverOs'] ? it['resource']['serverOs']['platform'] : it['resource']['osType']) || 'unknown').capitalize}},
              {"Cloud Type" => lambda {|it| it['zone']['zoneType']['name']}}
          ]
        elsif discovery['refType'] == 'computeZone'
          cols = [
              {"Status" => lambda {|it| format_status(it['resource']['status'])}},
              {"Cloud Type" => lambda {|it| it['zone']['zoneType']['name']}}
          ]
        end
        print as_pretty_table(discovery, cols, options)
      end

      max_bars = 20

      if discovery['type']['code'] == 'size'
        print_h2 "Usage"
        cols = [
            {"Plan" => lambda {|it| it['planBeforeAction'] ? it['planBeforeAction']['name'] : '--'}},
            {"Compute Usage" => lambda {|it|
              usage = (it['config'] ? it['config']['cpuUsageAvg'] || 0 : 0)
              "#{format_percent(usage)} of 100%".ljust(25, ' ') + generate_usage_bar(usage.round(2), 100, {:max_bars => max_bars}) + cyan
            }},
            {"Memory Usage" => lambda {|it|
              max = (it['resource'] || {})['maxMemory'] || (it['planBeforeAction'] || {})['maxMemory']
              usage = max > 0 ? (it['config']['usedMemoryAvg'] || 0).to_f / max * 100.0 : 0
              usage = 200.0 if usage > 200
              "#{format_bytes((it['config'] || {})['usedMemoryAvg'] || 0, 'auto', 1)} of #{format_bytes(max, 'auto', 1)}".ljust(25, ' ') + generate_usage_bar(usage, 100, {:max_bars => max_bars}) + cyan
            }}
        ]
        print_description_list(cols, discovery, options.merge({:wrap => false}))
        print_h2 "After Resize"

        if discovery['planAfterAction'] && discovery['planAfterAction']['id'] != (discovery['planBeforeAction'] || {})['id']
          cols = [
              {"Plan" => lambda {|it| it['planAfterAction'] ? it['planAfterAction']['name'] : '--'}},
              {"Compute Usage" => lambda {|it|
                usage = ((it['planAfterAction'] || {})['maxCores'] || 0) > 0 ? (((it['resource'] || {})['maxCores'] || (it['planBeforeAction'] || {})['maxCores']) || 0).to_f / it['planAfterAction']['maxCores'] * (it['config']['cpuUsageAvg'] || 0) : 0
                "#{format_percent(usage)} of 100%".ljust(25, ' ') + generate_usage_bar(usage.round(2), 100, {:max_bars => max_bars}) + cyan
              }},
              {"Memory Usage" => lambda {|it|
                max = (it['planAfterAction'] || {})['maxMemory'] || 0
                usage = max > 0 ? ((it['config'] || {})['usedMemoryAvg'] || 0).to_f / it['planAfterAction']['maxMemory'] * 100.0 : 0
                usage = 200.0 if usage > 200
                "#{format_bytes((it['config'] || {})['usedMemoryAvg'] || 0, 'auto', 1)} of #{format_bytes(max, 'auto', 1)}".ljust(25, ' ') + generate_usage_bar(usage, 100, {:max_bars => max_bars}) + cyan
              }}
          ]
        else
          if discovery['actionValueType'] == 'memory'
            cols = [
                {"Memory" => lambda {|it| format_bytes(it['actionValue'].to_i, 'auto')}},
                {"Compute Usage" => lambda {|it|
                  usage = (it['config'] ? it['config']['cpuUsageAvg'] || 0 : 0).round(2)
                  "#{format_percent(usage)} of 100%".ljust(25, ' ') + generate_usage_bar(usage, 100, {:max_bars => max_bars}) + cyan
                }},
                {"Memory Usage" => lambda {|it|
                  max = (it['actionValue'] || 0).to_f
                  usage = max > 0 ? ((it['config'] || {})['usedMemoryAvg'] || 0) / max * 100.0 : 0
                  usage = 200.0 if usage > 200
                  "#{format_bytes((it['config'] || {})['usedMemoryAvg'] || 0, 'auto', 1)} of #{format_bytes(max, 'auto', 1)}".ljust(25, ' ') + generate_usage_bar(usage, 100, {:max_bars => max_bars}) + cyan
                }}
            ]
          elsif discovery['actionValueType'] == 'cpu'
            cols = [
                {"Cores" => lambda {|it| it['actionValue']}},
                {"Compute Usage" => lambda {|it|
                  cores_before = it['beforeValue'] || (it['resource'] || {})['maxCores'] || (it['planBeforeAction'] || {})['maxCores'] || 0
                  usage = (it['actionValue'] || 0).to_f > 0 ? cores_before / it['actionValue'].to_f * ((it['config'] || {})['cpuUsageAvg'] || 0) : 0
                  "#{format_percent(usage)} of 100%".ljust(25, ' ') + generate_usage_bar(usage.round(2), 100, {:max_bars => max_bars}) + cyan
                }},
                {"Memory Usage" => lambda {|it|
                  max = (it['resource'] || {})['maxMemory'] || (it['planAfterAction'] || {})['maxMemory']
                  usage = max > 0 ? ((it['config'] || {})['usedMemoryAvg'] || 0) / max.to_f * 100.0 : 0
                  usage = 200.0 if usage > 200
                  "#{format_bytes((it['config'] || {})['usedMemoryAvg'] || 0, 'auto', 1)} of #{format_bytes(max, 'auto', 1)}".ljust(25, ' ') + generate_usage_bar(usage, 100, {:max_bars => max_bars}) + cyan
                }}
            ]
          end
        end
        print_description_list(cols, discovery, options.merge({:wrap => false}))
      elsif discovery['type']['code'] == 'shutdown'
        print_h2 "Usage"
        cols = [
            {"Plan" => lambda {|it| it['planBeforeAction'] ? it['planBeforeAction']['name'] : '--'}},
            {"Compute Usage" => lambda {|it|
              usage = (it['config'] ? it['config']['cpuUsageAvg'] || 0 : 0).round(2).to_s
              "#{format_percent(usage)} of 100%".ljust(25, ' ') + generate_usage_bar(usage, 100, {:max_bars => max_bars}) + cyan
            }},
            {"Network Usage" => lambda {|it|
              max = 1024 * 1024 * 1024
              usage = (it['config']['networkBandwidthAvg'] || 0) > 0 ? ((it['config']['networkBandwidthAvg'] || 0) / max.to_f) * 100 : 0
              "#{format_bytes((it['config']['networkBandwidthAvg'] || 0), 'auto', 1)} of #{format_bytes(max, 'auto', 1)}".ljust(25, ' ') + generate_usage_bar( usage, 100, {:max_bars => max_bars}) + cyan
            }}
        ]

        print_description_list(cols, discovery, options.merge({:wrap => false}))

        print_h2 "After Shutdown"
        cols = [
            {"Plan" => lambda {|it| it['planAfterAction'] ? it['planAfterAction']['name'] : '--'}},
            {"Monthly Savings" => lambda {|it| format_money(it['savings']['amount'], it['savings']['currency'], {:minus_color => red})}}
        ]
        print_description_list(cols, discovery, options)
      elsif discovery['type']['code'] == 'reservations'
        print_h2 "Current Cost"
        cols = [
            {"Current Cost" => lambda {|it| format_money((it['onDemandCost'] || 0) + (it['reservedCost'] || 0), discovery['savings']['currency'], {:minus_color => red})}},
            {"On-Demand Cost" => lambda {|it| format_money((it['onDemandCost'] || 0), discovery['savings']['currency'], {:minus_color => red})}},
            #{"Proposed Cost" => lambda {|it| format_money((it['recommendedCost'] || 0), discovery['savings']['currency'], {:minus_color => red})}}
        ]

        print_description_list(cols, discovery['config']['summary'], options)

        print_h2 "After Reservations"
        cols = [
            {"Proposed Cost" => lambda {|it| format_money((it['recommendedCost'] || 0), discovery['savings']['currency'], {:minus_color => red})}},
            {"Monthly Savings" => lambda {|it| format_money(discovery['savings']['amount'], discovery['savings']['currency'], {:minus_color => red})}},
            {"Savings Percent" => lambda {|it| format_percent(it['totalSavingsPercent'] * 100.0)}}
        ]
        print_description_list(cols, discovery['config']['summary'], options)

        cols = [
            {"Name" => lambda {|it| it['name']}},
            {"Region" => lambda {|it| it['region']}},
            {"Term" => lambda {|it| it['term']}},
            {"Current Cost" => lambda {|it| format_money(it['onDemandCost'], discovery['savings']['currency'], {:minus_color => red})}},
            {"Quantity" => lambda {|it| it['recommendedCount']}},
            {"Proposed Cost" => lambda {|it| format_money(it['recommendedCost'], discovery['savings']['currency'], {:minus_color => red})}},
            {"Savings" => lambda {|it| format_money(it['totalSavings'], discovery['savings']['currency'], {:minus_color => red})}}
        ]
        print_h2 "Details"
        print as_pretty_table(discovery['config']['detailList'], cols, options)
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def execute(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_remove_options(opts, options)
      opts.footer = "Get details about a specific discovery."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    _resolve_action(args[0], options)
  end

  def ignore(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_remove_options(opts, options)
      opts.footer = "Ignore discovery."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    _resolve_action(args[0], options, false)
  end

  private

  def _resolve_action(id, options, is_exec=true)
    begin
      discovery = find_discovery(id)

      if !discovery
        print_red_alert "Discovery #{id} not found"
        exit 1
      end

      if discovery['resolved'] || discovery['ignored']
        print_green_success "#{discovery['actionTitle'].capitalize} action for #{discovery['refName']} already resolved."
        return 0
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to #{is_exec ? 'execute' : 'ignore'} the #{discovery['actionTitle'].capitalize} action for #{discovery['refName']}?", options)
        return 9, "aborted command"
      end

      @guidance_interface.setopts(options)
      if options[:dry_run]
        print_dry_run (is_exec ? @guidance_interface.dry.exec(discovery['id']) : @guidance_interface.dry.ignore(discovery['id']))
        return
      end

      json_response = (is_exec ? @guidance_interface.exec(discovery['id']) : @guidance_interface.ignore(discovery['id']))

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Discovery successfully #{is_exec ? 'queued' : 'ignored'}"
        else
          print_red_alert "Error #{is_exec ? 'executing' : 'ignoring'} the #{discovery['actionTitle'].capitalize} action: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def find_discovery(id)
    @guidance_interface.get(id)['discovery']
  end

  def find_discovery_type(id)
    @guidance_interface.types()['types'].find {|it| it['id'].to_s == id.to_s || it['code'] == id || it['name'] == id}
  end

  def format_status(status)
    color = white
    if ['on', 'ok', 'provisioned', 'success', 'complete'].include? status
      color = green
    elsif ['off', 'failed', 'denied', 'cancelled', 'error'].include? status
      color = red
    elsif ['suspended', 'warning', 'deprovisioning', 'expired'].include? status
      color = yellow
    elsif ['available'].include? status
      color = blue
    end
    "#{color}#{status.capitalize}#{cyan}"
  end

  def action_title(type)
    {
        'shutdown' => 'Shutdown Resource',
        'size' => 'Resize Resource',
        'hostCapacity' => 'Add Capacity',
        'hostBalancing' => 'Balance Host',
        'datastoreCapacity' => 'Add Capacity',
        'reservations' => 'Reserve Compute'
    }[type['code']] || type['title']
  end
end
