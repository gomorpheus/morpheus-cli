require 'morpheus/cli/cli_command'

class Morpheus::Cli::Processes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProcessesHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::InfrastructureHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'process'

  register_subcommands :list, :get, {:'get-event' => :event_details}, :retry, :cancel

  # alias_subcommand :details, :get
  # set_default_subcommand :list
  
  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(options)
    @api_client = establish_remote_appliance_connection(options)
    @processes_interface = @api_client.processes
    #@instances_interface = @api_client.instances
    @clouds_interface = @api_client.clouds
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    #options[:show_output] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( nil, '--events', "Display sub processes (events)." ) do
        options[:show_events] = true
      end
      opts.on( nil, '--output', "Display process output." ) do
        options[:show_output] = true
      end
      opts.on(nil, '--details', "Display all details. Includes sub processes, output and error data is not truncated." ) do
        options[:show_events] = true
        options[:show_output] = true
        options[:details] = true
      end
      opts.on('--app APP', String, "Limit results to specific app(s).") do |val|
        params['appIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--instance INSTANCE', String, "Limit results to specific instance(s).") do |val|
        params['instanceIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--container CONTAINER', String, "Limit results to specific container(s).") do |val|
        params['containerIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--host HOST', String, "Limit results to specific host(s).") do |val|
        params['serverIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--server HOST', String, "Limit results to specific servers(s).") do |val|
        params['serverIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.add_hidden_option('--server')
      opts.on('--cloud CLOUD', String, "Limit results to specific cloud(s).") do |val|
        params['zoneIds'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
      end
      opts.on('--user USER', String, "Limit results to user(s).") do |val|
        #params['userId'] = val.split(',').collect {|it| it.to_s.strip }.reject { |it| it.empty? }
        options[:user] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List historical processes."
    end
    optparse.parse!(args)

    if args.count != 0
      puts optparse
      return 1
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      if params['instanceIds']
        params['instanceIds'] = params['instanceIds'].collect do |instance_id|
          if instance_id.to_s =~ /\A\d{1,}\Z/
            # just allow instance IDs
            instance_id.to_i
          else
            instance = find_instance_by_name_or_id(instance_id)
            if instance.nil?
              return 1, "instance not found for '#{instance_id}'" # never happens because find exits
            end
            instance['id']
          end
        end
      end
      if params['serverIds']
        params['serverIds'] = params['serverIds'].collect do |server_id|
          if server_id.to_s =~ /\A\d{1,}\Z/
            # just allow server IDs
            server_id.to_i
          else
            server = find_server_by_name_or_id(server_id)
            if server.nil?
              return 1, "server not found for '#{server_id}'" # never happens because find exits
            end
            server['id']
          end
        end
      end
      if params['appIds']
        params['appIds'] = params['appIds'].collect do |app_id|
          if app_id.to_s =~ /\A\d{1,}\Z/
            # just allow app IDs
            app_id.to_i
          else
            app = find_app_by_name_or_id(app_id)
            if app.nil?
              return 1, "app not found for '#{app_id}'" # never happens because find exits
            end
            app['id']
          end
        end
      end
      if params['zoneIds']
        params['zoneIds'] = params['zoneIds'].collect do |zone_id|
          if zone_id.to_s =~ /\A\d{1,}\Z/
            # just allow zone IDs
            zone_id.to_i
          else
            zone = find_cloud_by_name_or_id(zone_id)
            if zone.nil?
              return 1, "cloud not found for '#{zone_id}'" # never happens because find exits
            end
            zone['id']
          end
        end
      end
      if options[:user]
        user = find_available_user_option(options[:user])
        return 1, "user not found by '#{options[:user]}'" if user.nil?
        params['userId'] = user['id']
      end
      @processes_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @processes_interface.dry.list(params)
        return
      end
      json_response = @processes_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "processes")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processes'], options)
        return 0
      else

        title = "Process List"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if json_response['processes'].empty?
          print "#{cyan}No process history found.#{reset}\n\n"
          return 0
        else
          history_records = []
          json_response["processes"].each do |process|
            row = {
              id: process['id'],
              eventId: nil,
              uniqueId: process['uniqueId'],
              name: process['displayName'],
              description: process['description'],
              processType: process['processType'] ? (process['processType']['name'] || process['processType']['code']) : process['processTypeName'],
              createdBy: process['createdBy'] ? (process['createdBy']['displayName'] || process['createdBy']['username']) : '',
              startDate: format_local_dt(process['startDate']),
              duration: format_process_duration(process),
              status: format_process_status(process),
              error: format_process_error(process, options[:details] ? nil : 20),
              output: format_process_output(process, options[:details] ? nil : 20)
            }
            history_records << row
            process_events = process['events'] || process['processEvents']
            if options[:show_events]
              if process_events
                process_events.each do |process_event|
                  event_row = {
                    id: process['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event, options[:details] ? nil : 20),
                    output: format_process_output(process_event, options[:details] ? nil : 20)
                  }
                  history_records << event_row
                end
              else
                
              end
            end
          end
          columns = [
            {:id => {:display_name => "PROCESS ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error
          ]
          if options[:show_events]
            columns.insert(1, {:eventId => {:display_name => "EVENT ID"} })
          end
          if options[:show_output]
            columns << :output
          end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(history_records, columns, options)
          #print_results_pagination(json_response)
          if options[:show_events]
            print_results_pagination({size: history_records.size, total: history_records.size}, {:label => "process", :n_label => "processes"})
          else
            print_results_pagination(json_response, {:label => "process", :n_label => "processes"})
          end
          print reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    params = {}
    process_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on(nil, '--details', "Display more details. Shows everything, untruncated." ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details for a specific process.\n"
                    "[id] is required. This is the id of the process."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      process_id = args[0]
      params.merge!(parse_list_options(options))
      @processes_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @processes_interface.dry.get(process_id, params)
        return
      end
      json_response = @processes_interface.get(process_id, params)
      if options[:json]
        puts as_json(json_response, options, "process")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "process")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['process'], options)
        return 0
      else
        process = json_response["process"]
        title = "Process Details"
        subtitles = []
        subtitles << " Process ID: #{process_id}"
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        print_process_details(process, options)
  
        print_h2 "Process Events"
        process_events = process['events'] || process['processEvents'] || []
        history_records = []
        if process_events.empty?
          puts "#{cyan}No events found.#{reset}"
          print reset,"\n"
        else      
          process_events.each do |process_event|
            event_row = {
                    id: process_event['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event, options[:details] ? nil : 20),
                    output: format_process_output(process_event, options[:details] ? nil : 20)
                  }
            history_records << event_row
          end
          columns = [
            {:id => {:display_name => "EVENT ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error,
            :output
          ]
          print cyan
          print as_pretty_table(history_records, columns, options)
          print_results_pagination({size: process_events.size, total: process_events.size})
          print reset, "\n"
        end
        return 0, nil
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def retry(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Retry a process.
[id] is required. This is the id of a process.
Only a process that is failed or cancelled and is of a retryable type can be retried.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    # process = find_process_by_id(args[0])
    # return 1 if process.nil?
    process_id = args[0]
    payload = parse_payload(options)
    if payload.nil?
      payload = parse_passed_options(options)
      # prompt
    end
    confirm!("Are you sure you would like to retry process #{process_id}?", options)
    @processes_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @processes_interface.dry.retry(process_id, payload)
      return
    end
    json_response = @processes_interface.retry(process_id, payload)
    render_response(json_response, options) do
      print_green_success "Retrying process #{process_id}"
    end
    return 0, nil
  end

  def cancel(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Cancel a process.
[id] is required. This is the id of a process.
Only a process that is currently running and is of a cancellable type can be canceled.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    # process = find_process_by_id(args[0])
    # return 1 if process.nil?
    process_id = args[0]
    payload = parse_payload(options)
    if payload.nil?
      payload = parse_passed_options(options)
      # prompt
    end
    confirm!("Are you sure you would like to cancel process #{process_id}?", options)
    @processes_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @processes_interface.dry.cancel(process_id, payload)
      return
    end
    json_response = @processes_interface.cancel(process_id, payload)
    render_response(json_response, options) do
      print_green_success "Cancelling process #{process_id}"
    end
    return 0, nil
  end

  def event_details(args)
    options = {}
    params = {}
    process_event_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[event-id]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details for a specific process event.\n" +
                    "[event-id] is required. This is the id of the process event."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      process_event_id = args[0]
      params.merge!(parse_list_options(options))
      @processes_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @processes_interface.dry.get_event(process_event_id, params)
        return
      end
      json_response = @processes_interface.get_event(process_event_id, params)
      if options[:json]
        puts as_json(json_response, options, "processEvent")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processEvent")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processEvent'], options)
        return 0
      else
        process_event = json_response['processEvent'] || json_response['event']
        title = "Process Event Details"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        print_process_event_details(process_event, options)
        print reset, "\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

end
