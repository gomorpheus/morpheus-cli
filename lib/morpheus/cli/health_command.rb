require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/logs_helper'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::HealthCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LogsHelper
  set_command_name :health
  register_subcommands :get, :alarms, :'get-alarm', :'acknowledge-alarms', :'unacknowledge-alarms', :logs

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @health_interface = @api_client.health
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    options = {}
    params = {}
    live_health = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[-a] [options]")
      opts.on('-a', '--all', "Display all details: CPU, Memory, Database, etc." ) do
        options[:details] = true
        options[:show_cpu] = true
        options[:show_memory] = true
        options[:show_database] = true
        options[:show_elastic] = true
        options[:show_queue] = true
      end
      opts.on('--details', '--details', "Display all details: CPU, Memory, Database, etc." ) do
        options[:details] = true
        options[:show_cpu] = true
        options[:show_memory] = true
        options[:show_database] = true
        options[:show_elastic] = true
        options[:show_queue] = true
      end
      opts.add_hidden_option('--details') # prefer -a, --all
      opts.on('--cpu', "Display CPU details" ) do
        options[:show_cpu] = true
      end
      opts.on('--memory', "Display Memory details" ) do
        options[:show_memory] = true
      end
      opts.on('--database', "Display Database details" ) do
        options[:show_database] = true
      end
      opts.on('--elastic', "Display Elasticsearch details" ) do
        options[:show_elastic] = true
      end
      opts.on('--queue', "Display Queue (Rabbit) details" ) do
        options[:show_queue] = true
      end
      opts.on('--queues', "Display Queue (Rabbit) details" ) do
        options[:show_queue] = true
      end
      opts.on('--rabbit', "Display Queue (Rabbit) details" ) do
        options[:show_queue] = true
      end
      opts.add_hidden_option('--queues')
      opts.add_hidden_option('--rabbit')
      opts.on('--live', "Fetch Live Health Data. By default the last cached health data is returned. This also retrieves all elastic indices." ) do
        live_health = true
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get appliance health information." + "\n" +
                    "By default, only the health status and levels are displayed." + "\n" +
                    "Display more details with the options --cpu, --database, --memory, etc." + "\n" +
                    "Display all details with the -a option."
    end
    optparse.parse!(args)

    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      @health_interface.setopts(options)
      if options[:dry_run]
        print_dry_run(live_health ? @health_interface.dry.live(params) : @health_interface.dry.get(params))
        return 0
      end
      json_response = live_health ? @health_interface.live(params) : @health_interface.get(params)
      render_result = render_with_format(json_response, options, 'health')
      exit_code = json_response['success'] == true ? 0 : 1
      return exit_code if render_result

      health = json_response['health']
      subtitles = []
      if options[:details]
        subtitles << "Details"
      end
      if live_health
        subtitles << "(Live)"
      end
      print_h1 "Morpheus Health", subtitles, options
      # thin print below here
      options.merge!({thin:true})
      
      if health.nil?
        print yellow,"No health data returned.",reset,"\n"
        return 1
      end
      if health['elastic'] && health['elastic']['noticeMessage'].to_s != ""
        print cyan,health['elastic']['noticeMessage'],reset,"\n"
        print "\n"
      end

      #print_h2 "Health Summary", options
      print cyan
      health_summary_columns = {
        "Overall" => lambda {|it| format_health_status(it['cpu']['status']) rescue '' },
        "CPU" => lambda {|it| format_health_status(it['cpu']['status']) rescue '' },
        "Memory" => lambda {|it| format_health_status(it['memory']['status']) rescue '' },
        "Database" => lambda {|it| format_health_status(it['database']['status']) rescue '' },
        "Elastic" => lambda {|it| format_health_status(it['elastic']['status']) rescue '' },
        "Queue" => lambda {|it| format_health_status(it['rabbit']['status']) rescue '' },
      }
      print as_pretty_table(health, health_summary_columns, options)
      print "\n"
      
      # flash warnings
      if health['cpu'] && health['cpu']['status'] != 'ok' && health['cpu']['statusMessage']
        status_color = health['cpu']['status'] == 'error' ? red : yellow
        print status_color,health['cpu']['statusMessage'],reset,"\n"
      end
      if health['memory'] && health['memory']['status'] != 'ok' && health['memory']['statusMessage']
        status_color = health['memory']['status'] == 'error' ? red : yellow
        print status_color,health['memory']['statusMessage'],reset,"\n"
      end
      if health['database'] && health['database']['status'] != 'ok' && health['database']['statusMessage']
        status_color = health['database']['status'] == 'error' ? red : yellow
        print status_color,health['database']['statusMessage'],reset,"\n"
      end
      # if health['elastic'] && health['elastic']['noticeMessage'].to_s != ""
      #   print cyan,health['elastic']['noticeMessage'],reset,"\n"
      # end
      if health['elastic'] && health['elastic']['status'] != 'ok' && health['elastic']['statusMessage']
        status_color = health['elastic']['status'] == 'error' ? red : yellow
        print status_color,health['elastic']['statusMessage'],reset,"\n"
      end
      if health['rabbit'] && health['rabbit']['status'] != 'ok' && health['rabbit']['statusMessage']
        status_color = health['rabbit']['status'] == 'error' ? red : yellow
        print status_color,health['rabbit']['statusMessage'],reset,"\n"
      end

      print_h2 "Health Levels", options
      print cyan
      health_levels_columns = {
        "Morpheus CPU" => lambda {|it| format_percent(it['cpu']['cpuLoad'].to_f, 0) rescue '' },
        "System CPU" => lambda {|it| format_percent(it['cpu']['cpuTotalLoad'].to_f, 0) rescue '' },
        "Morpheus Memory" => lambda {|it| format_percent(it['memory']['memoryPercent'].to_f * 100, 0) rescue '' },
        "System Memory" => lambda {|it| format_percent(it['memory']['systemMemoryPercent'].to_f * 100, 0) rescue '' },
        "Used Swap" => lambda {|it| format_percent(it['memory']['swapPercent'].to_f * 100, 0) rescue '' },
      }
      print as_pretty_table(health, health_levels_columns, options)
      # print "\n"

      if options[:show_cpu]
        # CPU
        if health['cpu'].nil?
          print yellow,"No cpu health information returned.",reset,"\n"
        else
          print_h2 "CPU", options
          print cyan
          cpu_columns = {
            "Processor Count" => lambda {|it| it['processorCount'] rescue '' },
            "Process Time" => lambda {|it| format_human_duration(it['processTime'].to_f / 1000) rescue '' },
            "Morpheus CPU" => lambda {|it| (it['cpuLoad'].to_f.round(2).to_s + '%') rescue '' },
            "System CPU" => lambda {|it| (it['cpuTotalLoad'].to_f.round(2).to_s + '%') rescue '' },
            "System Load" => lambda {|it| (it['systemLoad'].to_f.round(3)) rescue '' },
          }
          #print as_pretty_table(health['cpu'], cpu_columns, options)
          print_description_list(cpu_columns, health['cpu'], options)
        end
      end

      # Memory
      if options[:show_memory]
        if health['memory'].nil?
          print yellow,"No memory health information returned.",reset,"\n"
        else
          print_h2 "Memory", options
          print cyan
          memory_columns = {
            "Morpheus Memory" => lambda {|it| format_bytes_short(it['totalMemory']) rescue '' },
            "Morpheus Used Memory" => lambda {|it| format_bytes_short(it['usedMemory']) rescue '' },
            "Morpheus Free Memory" => lambda {|it| format_bytes_short(it['freeMemory']) rescue '' },
            "Morpheus Memory Usage" => lambda {|it| format_percent(it['memoryPercent'].to_f * 100) rescue '' },
            "System Memory" => lambda {|it| format_bytes_short(it['systemMemory']) rescue '' },
            "System Used Memory" => lambda {|it| format_bytes_short(it['committedMemory']) rescue '' },
            "System Free Memory" => lambda {|it| format_bytes_short(it['systemFreeMemory']) rescue '' },
            "System Memory Usage" => lambda {|it| format_percent(it['systemMemoryPercent'].to_f * 100) rescue '' },
            "System Swap" => lambda {|it| format_bytes_short(it['systemSwap']) rescue '' },
            "Free Swap" => lambda {|it| format_bytes_short(it['systemFreeSwap']) rescue '' },
            #"Used Swap" => lambda {|it| format_percent(it['swapPercent'].to_f * 100) rescue '' }
            # "System Load" => lambda {|it| (it['systemLoad'].to_f(3)) rescue '' },
          }
          #print as_pretty_table(health['memory'], memory_columns, options)
          print_description_list(memory_columns, health['memory'], options)
        end
      end

      # Database (mysql)
      if options[:show_database]
        if health['database'].nil?
          print yellow,"No database health information returned.",reset,"\n"
        else
          print_h2 "Database", options
          print cyan
          database_columns = {
            "Lifetime Connections" => lambda {|it| it['stats']['Connections'] rescue '' },
            "Aborted Connections" => lambda {|it| it['stats']['Aborted_connects'] rescue '' },
            "Max Used Connections" => lambda {|it| it['stats']['Max_used_connections'] rescue '' },
            "Max Connections" => lambda {|it| it['maxConnections'] rescue '' },
            "Threads Running" => lambda {|it| it['stats']['Threads_running'] rescue '' },
            "Threads Connected" => lambda {|it| it['stats']['Threads_connected'] rescue '' },
            "Slow Queries" => lambda {|it| it['stats']['Slow_queries'] rescue '' },
            "Temp Tables" => lambda {|it| it['stats']['Created_tmp_disk_tables'] rescue '' },
            "Handler Read First" => lambda {|it| it['stats']['Handler_read_first'] rescue '' },
            "Buffer Pool Free" => lambda {|it| it['stats']['Innodb_buffer_pool_wait_free'] rescue '' },
            "Open Tables" => lambda {|it| it['stats']['Open_tables'] rescue '' },
            "Table Scans" => lambda {|it| it['stats']['Select_scan'] rescue '' },
            "Full Joins" => lambda {|it| it['stats']['Select_full_join'] rescue '' },
            "Key Read Requests" => lambda {|it| it['stats']['Key_read_requests'] rescue '' },
            "Key Reads" => lambda {|it| it['stats']['Key_reads'] rescue '' },
            "Engine Waits" => lambda {|it| it['stats']['Innodb_log_waits'] rescue '' },
            "Lock Waits" => lambda {|it| it['stats']['Table_locks_waited'] rescue '' },
            "Handler Read Rnd" => lambda {|it| it['stats']['Handler_read_rnd'] rescue '' },
            "Engine IO Writes" => lambda {|it| it['stats']['Innodb_data_writes'] rescue '' },
            "Engine IO Reads" => lambda {|it| it['stats']['Innodb_data_reads'] rescue '' },
            "Engine IO Double Writes" => lambda {|it| it['stats']['Innodb_dblwr_writes'] rescue '' },
            "Engine Log Writes" => lambda {|it| it['stats']['Innodb_log_writes'] rescue '' },
            "Engine Memory" => lambda {|it| format_bytes_short(it['innodbStats']['largeMemory']) rescue '' },
            "Dictionary Memory" => lambda {|it| format_bytes_short(it['innodbStats']['dictionaryMemory']) rescue '' },
            "Buffer Pool Size" => lambda {|it| it['innodbStats']['bufferPoolSize'] rescue '' },
            "Free Buffers" => lambda {|it| it['innodbStats']['freeBuffers'] rescue '' },
            "Database Pages" => lambda {|it| it['innodbStats']['databasePages'] rescue '' },
            "Old Pages" => lambda {|it| it['innodbStats']['oldPages'] rescue '' },
            "Dirty Page Percent" => lambda {|it| format_percent(it['innodbStats']['dirtyPagePercent'] ? it['innodbStats']['dirtyPagePercent'] : '') rescue '' },
            "Max Dirty Pages" => lambda {|it| format_percent(it['innodbStats']['maxDirtyPagePercent'].to_f) rescue '' },
            "Pending Reads" => lambda {|it| format_number(it['innodbStats']['pendingReads']) rescue '' },
            "Insert Rate" => lambda {|it| format_rate(it['innodbStats']['insertsPerSecond'].to_f) rescue '' },
            "Update Rate" => lambda {|it| format_rate(it['innodbStats']['updatesPerSecond'].to_f) rescue '' },
            "Delete Rate" => lambda {|it| format_rate(it['innodbStats']['deletesPerSecond'].to_f) rescue '' },
            "Read Rate" => lambda {|it| format_rate(it['innodbStats']['readsPerSecond']) rescue '' },
            "Buffer Hit Rate" => lambda {|it| format_percent(it['innodbStats']['bufferHitRate'].to_f) rescue '' },
            "Read Write Ratio" => lambda {|it| 
              rw_ratio = ""
              begin
                total_writes = (it['stats']['Com_update'].to_i) + (it['stats']['Com_insert'].to_i) + (it['stats']['Com_delete'].to_f)
                total_reads = (it['stats']['Com_select'].to_i)
                if total_writes > 0
                  rw_ratio = (total_reads.to_f / total_writes.to_f).round(2).to_s
                end
              rescue => ex
                puts ex
              end
              rw_ratio
            },
            "Uptime" => lambda {|it| (it['stats']['Uptime'] ? format_human_duration(it['stats']['Uptime'].to_i) : '') rescue '' },
          }
          
          print_description_list(database_columns, health['database'], options)
          #print as_pretty_table(health['database'], database_columns, options)

        end
      end

      # Elasticsearch
      if options[:show_elastic]
        if health['elastic'].nil?
          print yellow,"No elastic health information returned.",reset,"\n\n"
        else
          print_h2 "Elastic", options
          print cyan

          elastic_columns = {
            "Status" => 'status',
            # "Status" => lambda {|it| format_health_status(it['status']) rescue '' },
            # "Status" => lambda {|it| 
            #   begin
            #     if it['statusMessage'].to_s != ""
            #       format_health_status(it['status']).to_s + " - " + it['statusMessage'] 
            #     else
            #       format_health_status(it['status'])
            #     end
            #   rescue => ex
            #     ''
            #   end
            # },
            "Cluster" => lambda {|it| it['stats']['clusterName'] rescue '' },
            "Node Count" => lambda {|it| it['stats']['nodeTotal'] rescue '' },
            "Data Nodes" => lambda {|it| it['stats']['nodeData'] rescue '' },
            "Shards" => lambda {|it| it['stats']['shards'] rescue '' },
            "Primary Shards" => lambda {|it| it['stats']['primary'] rescue '' },
            "Relocating Shards" => lambda {|it| it['stats']['relocating'] rescue '' },
            "Initializing" => lambda {|it| it['stats']['initializing'] rescue '' },
            "Unassigned" => lambda {|it| it['stats']['unassigned'] rescue '' },
            "Pending Tasks" => lambda {|it| it['stats']['pendingTasks'] rescue '' },
            "Active Shards" => lambda {|it| it['stats']['activePercent'] rescue '' },
          }
          
          print_description_list(elastic_columns, health['elastic'], options)
          #print as_pretty_table(health['elastic'], elastic_columns, options)

          elastic_nodes_columns = [
            {"NODE" => lambda {|it| it['name'] } },
            {"MASTER" => lambda {|it| it['master'] == '*' } },
            {"LOCATION" => lambda {|it| it['ip'] } },
            {"RAM" => lambda {|it| it['ramPercent'] } },
            {"HEAP" => lambda {|it| it['heapPercent'] } },
            {"CPU USAGE" => lambda {|it| it['cpuCount'] } },
            {"1M LOAD" => lambda {|it| it['loadOne'] } },
            {"5M LOAD" => lambda {|it| it['loadFive'] } },
            {"15M LOAD" => lambda {|it| it['loadFifteen'] } }
          ]

          print_h2 "Elastic Nodes"
          if health['elastic']['nodes'].nil? || health['elastic']['nodes'].empty?
            print yellow,"No nodes found.",reset,"\n\n"
          else
            print as_pretty_table(health['elastic']['nodes'], elastic_nodes_columns, options)
          end
          
          elastic_indices_columns = [
            {"Health".upcase => lambda {|it| format_index_health(it['health']) } },
            {"Index".upcase => lambda {|it| it['index']} },
            {"Primary".upcase => lambda {|it| it['primary'] } },
            {"Replicas".upcase => lambda {|it| it['replicas'] } },
            {"Doc Count".upcase => lambda {|it| format_number(it['count']) } },
            {"Primary Size".upcase => lambda {|it| it['primarySize'] } },
            {"Total Size".upcase => lambda {|it| it['totalSize'] } },
          ]

          # when the api returns indices, it will include badIndices, so don't show both.
          if health['elastic']['indices'] && health['elastic']['indices'].size > 0
            print_h2 "Elastic Indices"
            if health['elastic']['indices'].nil? || health['elastic']['indices'].empty?
              print yellow,"No indices found.",reset,"\n\n"
            else
              print cyan
              print as_pretty_table(health['elastic']['indices'], elastic_indices_columns, options)
            end
          else
            print_h2 "Bad Elastic Indices"
            if health['elastic']['badIndices'].nil? || health['elastic']['badIndices'].empty?
              # print cyan,"No bad indices found.",reset,"\n\n"
            else
              print cyan
              print as_pretty_table(health['elastic']['badIndices'], elastic_indices_columns, options)
            end
          end


        end
      end

      # Queues (rabbit)
      if options[:show_queue]
        print_h2 "Queue (Rabbit)", options
        if health['rabbit'].nil?
          print yellow,"No rabbit queue health information returned.",reset,"\n\n"
        else
          print cyan

          rabbit_summary_columns = {
            "Status" => lambda {|it| 
              begin
                if it['statusMessage'].to_s != ""
                  format_health_status(it['status']).to_s + " - " + it['statusMessage'] 
                else
                  format_health_status(it['status'])
                end
              rescue => ex
                ''
              end
            },
            "Queues" => lambda {|it| it['queues'].size rescue '' },
            "Busy Queues" => lambda {|it| it['busyQueues'].size rescue '' },
            "Error Queues" => lambda {|it| it['errorQueues'].size rescue '' }
          }
          
          print_description_list(rabbit_summary_columns, health['rabbit'], options)
          #print as_pretty_table(health['rabbit'], rabbit_summary_columns, options)

          print_h2 "Queues"
          queue_columns = [
            {"Status".upcase => lambda {|it| 
              # hrmm
              status_string = it['status'].to_s.downcase # || 'green'
              if status_string == 'warning'
                "#{yellow}WARNING#{cyan}"
              elsif status_string == 'error'
                "#{red}ERROR#{cyan}"
              elsif status_string == 'ok'
                "#{green}OK#{cyan}"
              else
                # hrmm
                it['status']
              end
            } },
            {"Name".upcase => lambda {|it| it['name']} },
            {"Count".upcase => lambda {|it| format_number(it['count']) } }
          ]
          
          if health['rabbit'].nil? || health['rabbit']['queues'].nil? || health['rabbit']['queues'].empty?
            print yellow,"No queues found.",reset,"\n\n"
          else
            print cyan
            print as_pretty_table(health['rabbit']['queues'], queue_columns, options)
          end

          if health['rabbit'].nil? || health['rabbit']['busyQueues'].nil? || health['rabbit']['busyQueues'].empty?
            # print cyan,"No busy queues found.",reset,"\n"
          else
            print_h2 "Busy Queues"
            print cyan
            print as_pretty_table(health['rabbit']['busyQueues'], queue_columns, options)
          end

          if health['rabbit'].nil? || health['rabbit']['errorQueues'].nil? || health['rabbit']['errorQueues'].empty?
            # print cyan,"No error queues found.",reset,"\n"
          else
            print_h2 "Error Queues"
            print cyan
            print as_pretty_table(health['rabbit']['errorQueues'], queue_columns, options)
          end

        end

      end


      print "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    params = {}
    start_date, end_date = nil, nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--level VALUE', String, "Log Level. DEBUG,INFO,WARN,ERROR") do |val|
        params['level'] = params['level'] ? [params['level'], val].flatten : val
      end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        start_date = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        end_date = parse_time(val) #.utc.iso8601
      end
      opts.on('--table', '--table', "Format output as a table.") do
        options[:table] = true
      end
      opts.on('-a', '--all', "Display all details: entire message." ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List health logs. These are the logs of the morpheus appliance itself."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      # params['startDate'] = start_date.utc.iso8601 if start_date
      # params['endDate'] = end_date.utc.iso8601 if end_date
      params['startMs'] = (start_date.to_i * 1000) if start_date
      params['endMs'] = (end_date.to_i * 1000) if end_date
      params.merge!(parse_list_options(options))
      @health_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @health_interface.dry.logs(params)
        return 0
      end
      json_response = @health_interface.logs(params)
      render_result = json_response['logs'] ? render_with_format(json_response, options, 'logs') : render_with_format(json_response, options, 'data')
      return 0 if render_result
      logs = json_response['data'] || json_response['logs']
      title = "Morpheus Health Logs"
      subtitles = []
      if params['level']
        subtitles << "Level: #{params['level']}"
      end
      if start_date
        subtitles << "Start: #{start_date}"
      end
      if end_date
        subtitles << "End: #{end_date}"
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      
      if logs.empty?
        print "#{cyan}No logs found.#{reset}\n"
      else
        print format_log_records(logs, options, false)
        print_results_pagination({'meta'=>{'total'=>(json_response['total']['value'] rescue json_response['total']),'size'=>logs.size,'max'=>(json_response['max'] || options[:max]),'offset'=>(json_response['offset'] || options[:offset] || 0)}})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def alarms(args)
    options = {}
    params = {}
    start_date, end_date = nil, nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--category VALUE', String, "Filter by Alarm Category. datastore, computeZone, computeServer, etc.") do |val|
        params['alarmCategory'] = params['alarmCategory'] ? [params['alarmCategory'], val].flatten : val
      end
      opts.on('--status VALUE', String, "Filter by status. warning, error") do |val|
        params['status'] = params['status'] ? [params['status'], val].flatten : val
      end
      opts.on('--acknowledged', '--acknowledged', "Filter by acknowledged. By default only open alarms are returned.") do
        params['alarmStatus'] = 'acknowledged'
      end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        start_date = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        end_date = parse_time(val) #.utc.iso8601
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List health alarms."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      params['startDate'] = start_date.utc.iso8601 if start_date
      params['endDate'] = end_date.utc.iso8601 if end_date
      params.merge!(parse_list_options(options))
      @health_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @health_interface.dry.list_alarms(params)
        return 0
      end
      json_response = @health_interface.list_alarms(params)
      render_result = render_with_format(json_response, options, 'alarms')
      return 0 if render_result
      alarms = json_response['alarms']
      title = "Morpheus Health Alarms"
      subtitles = []
      # if params['category']
      #   subtitles << "Category: #{params['category']}"
      # end
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
      if alarms.empty?
        print cyan,"No alarms found.",reset,"\n"
      else
        alarm_columns = [
          {"ID" => lambda {|alarm| alarm['id'] } },
          {"STATUS" => lambda {|alarm| format_health_status(alarm['status']) } },
          {"RESOURCE" => lambda {|alarm| alarm['resourceName'] || alarm['refName'] } },
          {"INFO" => lambda {|alarm| alarm['name'] } },
          {"START DATE" => lambda {|alarm| format_local_dt(alarm['startDate']) } },
          {"DURATION" => lambda {|alarm| format_duration(alarm['startDate'], alarm['acknoDate'] || Time.now) } },
        ]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(alarms, alarm_columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_alarm(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a health alarm.\n[id] is required. Health Alarm ID"
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    
    @health_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @health_interface.dry.get_alarm(args[0], params)
      return 0
    end
    json_response = @health_interface.get_alarm(args[0], params)
    render_result = render_with_format(json_response, options, 'alarm')
    return 0 if render_result
    if json_response['alarm'].nil?
      print_red_alert "Alarm not found by id #{args[0]}"
      return 1
    end
    print_h1 "Alarm Details"
    print cyan
    alarm_columns = [
      {"ID" => lambda {|alarm| alarm['id'] } },
      {"Status" => lambda {|alarm| format_health_status(alarm['status']) } },
      {"Resource" => lambda {|alarm| alarm['resourceName'] || alarm['refName'] } },
      {"Info" => lambda {|alarm| alarm['name'] } },
      {"Start Date" => lambda {|alarm| format_local_dt(alarm['startDate']) } },
      {"Duration" => lambda {|alarm| format_duration(alarm['startDate'], alarm['acknowledgedDate'] || Time.now) } },
      {"Acknowledged Date" => lambda {|alarm| format_local_dt(alarm['acknowledgedDate']) } },
      {"Acknowledged" => lambda {|alarm| format_boolean(alarm['acknowledged']) } }
    ]
    print_description_list(alarm_columns, json_response['alarm'])
    print reset,"\n"
    return 0

  end

  def acknowledge_alarms(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[alarm] [options]")
      opts.on('-a', '--all', "Acknowledge all open alarms. This can be used instead of passing specific alarms.") do
        params['all'] = true
      end
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
      opts.footer = "Acknowledge health alarm(s).\n[alarm] is required. Alarm ID, supports multiple arguments."
    end
    optparse.parse!(args)

    if params['all']
      # updating all
      if args.count > 0
        raise_command_error "wrong number of arguments, --all option expects 0 and got (#{args.count}) #{args}\n#{optparse}"
      end
    else
      # updating 1-N ids
      if args.count < 0
        raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args}\n#{optparse}"
      end
      params['ids'] = args.collect {|arg| arg }
    end
    connect(options)
    begin
      # validate ids
      if params['ids']
        parsed_id_list = []
        params['ids'].each do |alarm_id|
          alarm = find_health_alarm_by_name_or_id(alarm_id)
          if alarm.nil?
            # print_red_alert "Alarm not found by id #{args[0]}"
            return 1
          end
          parsed_id_list << alarm['id']
        end
        params['ids'] = parsed_id_list.uniq
      end

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(passed_options) unless passed_options.empty?
      else
        payload = {}
        # allow arbitrary -O options
        payload.deep_merge!(passed_options) unless passed_options.empty?
      end
      id_list = params['ids'] || []
      confirm_msg = params['all'] ? "Are you sure you want to acknowledge all open alarms?" : "Are you sure you want to acknowledge the #{id_list.size == 1 ? 'alarm' : 'alarms'} #{anded_list(id_list)}?"
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm(confirm_msg)
        return 9, "aborted command"
      end
      @health_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @health_interface.dry.acknowledge_alarms(params, payload)
        return
      end
      json_response = @health_interface.acknowledge_alarms(params, payload)
      render_result = render_with_format(json_response, options)
      exit_code = 0 # json_response['success'] == true ? 0 : 1
      return exit_code if render_result

      if params['all']
        print_green_success "Acknowledged all alarms"
      else
        print_green_success "Acknowledged #{id_list.size == 1 ? 'alarm' : 'alarms'} #{anded_list(id_list)}"
      end
      return exit_code
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def unacknowledge_alarms(args)
    options = {}
    params = {acknowledged:false}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[alarm] [options]")
      # opts.on('-a', '--all', "Acknowledge all open alarms. This can be used instead of passing specific alarms.") do
      #   params['all'] = true
      # end
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :remote])
      opts.footer = "Unacknowledge health alarm(s).\n[alarm] is required. Alarm ID, supports multiple arguments."
    end
    optparse.parse!(args)

    if params['all']
      # updating all
      if args.count > 0
        raise_command_error "wrong number of arguments, --all option expects 0 and got (#{args.count}) #{args}\n#{optparse}"
      end
    else
      # updating 1-N ids
      if args.count < 0
        raise_command_error "wrong number of arguments, expected 1-N and got (#{args.count}) #{args}\n#{optparse}"
      end
      params['ids'] = args.collect {|arg| arg }
    end
    connect(options)
    begin
      # validate ids
      if params['ids']
        parsed_id_list = []
        params['ids'].each do |alarm_id|
          alarm = find_health_alarm_by_name_or_id(alarm_id)
          if alarm.nil?
            # print_red_alert "Alarm not found by id #{args[0]}"
            return 1
          end
          parsed_id_list << alarm['id']
        end
        params['ids'] = parsed_id_list.uniq
      end

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(passed_options) unless passed_options.empty?
      else
        payload = {}
        # allow arbitrary -O options
        payload.deep_merge!(passed_options) unless passed_options.empty?
      end
      id_list = params['ids'] || []
      confirm_msg = params['all'] ? "Are you sure you want to unacknowledge all alarms?" : "Are you sure you want to unacknowledge the #{id_list.size == 1 ? 'alarm' : 'alarms'} #{anded_list(id_list)}?"
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm(confirm_msg)
        return 9, "aborted command"
      end
      @health_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @health_interface.dry.acknowledge_alarms(params, payload)
        return
      end
      json_response = @health_interface.acknowledge_alarms(params, payload)
      render_result = render_with_format(json_response, options)
      exit_code = 0 # json_response['success'] == true ? 0 : 1
      return exit_code if render_result

      if params['all']
        print_green_success "Acknowledged all alarms"
      else
        print_green_success "Acknowledged #{id_list.size == 1 ? 'alarm' : 'alarms'} #{anded_list(id_list)}"
      end
      return exit_code
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
  private

  def find_health_alarm_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_health_alarm_by_id(val)
    else
      return find_health_alarm_by_name(val)
    end
  end

  def find_health_alarm_by_id(id)
    raise "#{self.class} has not defined @health_interface" if @health_interface.nil?
    begin
      json_response = @health_interface.get_alarm(id)
      return json_response['alarm']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Alarm not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_health_alarm_by_name(name)
    raise "#{self.class} has not defined @health_interface" if @health_interface.nil?
    alarms = @health_interface.list_alarms({name: name.to_s})['alarms']
    if alarm.empty?
      print_red_alert "Alarm not found by name #{name}"
      return nil
    elsif alarms.size > 1
      print_red_alert "#{alarms.size} alarms found by name #{name}"
      print as_pretty_table(alarms, [:id,:name], {color:red})
      print reset,"\n"
      return nil
    else
      return alarms[0]
    end
  end

  def format_health_status(val, return_color=cyan)
    out = ""
    status_string = val.to_s.downcase
    if(status_string)
      if(status_string == 'ok' || status_string == 'running')
        out << "#{green}#{status_string.upcase}#{return_color}"
      elsif(status_string == 'error' || status_string == 'offline')
        out << "#{red}#{status_string.upcase}#{return_color}"
      elsif status_string == 'syncing'
        out << "#{cyan}#{status_string.upcase}#{return_color}"
      else
        out << "#{yellow}#{status_string.upcase}#{return_color}"
      end
    end
    out
  end

  # this is for weird elastic status values that are actually colors
  def format_index_health(val, return_color=cyan)
    # hrmm
    status_string = val.to_s.downcase # || 'green'
    if status_string == 'warning' || status_string == 'yellow'
      "#{yellow}WARNING#{cyan}"
    elsif status_string == 'error' || status_string == 'red'
      "#{red}ERROR#{cyan}"
    elsif status_string == 'ok' || status_string == 'green'
      "#{green}OK#{cyan}"
    else
      # hrmm
      it['status']
    end
  end

  def format_queue_status(val, return_color=cyan)
    # hrmm
    status_string = val.to_s.downcase # || 'ok'
    if status_string == 'warning'
      "#{yellow}WARNING#{cyan}"
    elsif status_string == 'error'
      "#{red}ERROR#{cyan}"
    elsif status_string == 'ok'
      "#{green}OK#{cyan}"
    else
      # hrmm
      it['status']
    end
  end

end
