require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::ReportsCommand
  include Morpheus::Cli::CliCommand
  set_command_name :reports

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @reports_interface = @api_client.reports
  end

  register_subcommands :list, :get, :run, :view, :export, :remove, :types
  
  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '--type CODE', String, "Report Type code(s)" ) do |val|
        params['reportType'] = val.to_s.split(",").compact.collect {|it| it.strip }
      end
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      
      @reports_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @reports_interface.dry.list(params)
        return
      end

      json_response = @reports_interface.list(params)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      report_results = json_response['reportResults']
      
      title = "Morpheus Report History"
      subtitles = []
      if params['type']
        subtitles << "Type: #{params[:type]}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      if report_results.empty?
        print cyan, "No report results found", reset, "\n"
      else
        columns = {
          "ID" => 'id',
          "TITLE" => lambda {|it| truncate_string(it['reportTitle'], 50) },
          "FILTERS" => lambda {|it| truncate_string(it['filterTitle'], 30) },
          "REPORT TYPE" => lambda {|it| it['type'].is_a?(Hash) ? it['type']['name'] : it['type'] },
          "DATE RUN" => lambda {|it| format_local_dt(it['dateCreated']) },
          "CREATED BY" => lambda {|it| it['createdBy'].is_a?(Hash) ? it['createdBy']['username'] : it['createdBy'] },
          "STATUS" => lambda {|it| format_report_status(it) }
        }
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(report_results, columns, options)
        print reset
        print_results_pagination(json_response)
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    original_args = args.dup
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on('--refresh [SECONDS]', String, "Refresh until status is ready,failed. Default interval is 5 seconds.") do |val|
        options[:refresh_until_status] ||= "ready,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      opts.on('--rows', '--rows', "Print Report Data rows too.") do
        options[:show_data_rows] = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :outfile, :dry_run, :remote])
      opts.footer = "Get details about a report result." + "\n"
                  + "[id] is required. This is the id of the report result."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [id]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      @reports_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @reports_interface.dry.get(args[0].to_i)
        return 0
      end

      report_result = find_report_result_by_id(args[0])
      return 1 if report_result.nil?
      json_response = {'reportResult' => report_result}  # skip redundant request
      # json_response = @reports_interface.get(report['id'])
      #report_result = json_response['reportResult']

      # if options[:json]
      #   puts as_json(json_response, options)
      #   return 0
      # end
      # render_with_format() handles json,yaml,csv,outfile,etc
      render_result = render_with_format(json_response, options, 'reportResult')
      if render_result
        #return render_result
      else
        print_h1 "Morpheus Report Details"
        print cyan
        
        description_cols = {
          "ID" => 'id',
          "Title" => lambda {|it| it['reportTitle'] },
          "Filters" => lambda {|it| it['filterTitle'] },
          "Report Type" => lambda {|it| it['type'].is_a?(Hash) ? it['type']['name'] : it['type'] },
          "Date Run" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Created By" => lambda {|it| it['createdBy'].is_a?(Hash) ? it['createdBy']['username'] : it['createdBy'] },
          "Status" => lambda {|it| format_report_status(it) }
        }
        print_description_list(description_cols, report_result)

        # todo: 
        # 1. format raw output better.  
        # 2. write rendering methods for all the various types...
        if options[:show_data_rows]
          print_h2 "Report Data Rows"
          print cyan
          if report_result['rows']
            # report_result['rows'].each_with_index do |row, index|
            #   print "#{index}: ", row, "\n"
            # end
            term_width = current_terminal_width()
            data_width = term_width.to_i - 30
            if data_width < 0
              data_wdith = 10
            end
            puts as_pretty_table(report_result['rows'], {
              "ID" => lambda {|it| it['id'] },
              "SECTION" => lambda {|it| it['section'] },
              "DATA" => lambda {|it| truncate_string(it['data'], data_width) }
            })
            
          else
            print yellow, "No report data found.", reset, "\n"
          end
        end
        
        print reset,"\n"
      end

      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = 5
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(report_result['status'])
          print cyan, "Refreshing in #{options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          get(original_args)
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def run(args)
    params = {}
    do_refresh = true
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type] [options]")
      opts.on( '--type CODE', String, "Report Type code" ) do |val|
        options[:options]['type'] = val
      end
      # opts.on( '--title TITLE', String, "Title for the report" ) do |val|
      #   options[:options]['reportTitle'] = val
      # end
      opts.on(nil, '--no-refresh', "Do not refresh until finished" ) do
        do_refresh = false
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Run a report to generate a new result." + "\n" +
                    "[type] is required. This is code of the report type."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    if args[0]
      options[:options]['type'] = args[0]
    end
    connect(options)
    begin

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'report' => passed_options})  unless passed_options.empty?
      else
        # prompt for resource folder options
        payload = {
          'report' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'report' => passed_options})  unless passed_options.empty?

        # Report Type
        @all_report_types ||= @reports_interface.types({max: 1000})['reportTypes'] || []
        report_types_dropdown = @all_report_types.collect {|it| {"name" => it["name"], "value" => it["code"]} }
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Report Type', 'type' => 'select', 'selectOptions' => report_types_dropdown, 'required' => true}], options[:options], @api_client)
        payload['report']['type'] = v_prompt['type']
        # convert name/code/id to code
        report_type = find_report_type_by_name_or_code_id(payload['report']['type'])
        return 1 if report_type.nil?
        payload['report']['type'] = report_type['code']

        # Report Types need to tell us what the available filters are...

        # Start Date
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'startDate', 'fieldLabel' => 'Start Date', 'type' => 'text', 'required' => false}], options[:options])
        payload['report']['startDate'] = v_prompt['startDate'] unless v_prompt['startDate'].to_s.empty?

        # End Date
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'endDate', 'fieldLabel' => 'End Date', 'type' => 'text', 'required' => false}], options[:options])
        payload['report']['endDate'] = v_prompt['endDate'] unless v_prompt['endDate'].to_s.empty?

      end

      @reports_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @reports_interface.dry.create(payload)
        return 0
      end
      json_response = @reports_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Created report result #{json_response['reportResult']['id']}"
      if do_refresh
        get([json_response['reportResult']['id'], "--refresh"])
      else
        get([json_response['reportResult']['id']])
      end
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "View a report result in a web browser" + "\n" +
                    "[id] is required. This is id of the report result."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      report_result = find_report_result_by_id(args[0])
      return 1 if report_result.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/operations/reports/#{report_result['type']['code']}/reportResults/#{report_result['id']}"

      open_command = nil
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        open_command = "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        open_command = "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        open_command = "xdg-open #{link}"
      end

      if options[:dry_run]
        puts "system: #{open_command}"
        return 0
      end

      system(open_command)
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def export(args)
    params = {}
    report_format = 'json'
    options = {}
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id] [file]")
      build_common_options(opts, options, [:dry_run, :remote])
      opts.on( '--format VALUE', String, "Report Format for exported file, json or csv. Default is json." ) do |val|
        report_format = val
      end
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        do_overwrite = true
        # do_mkdir = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        do_mkdir = true
      end
      opts.footer = "Export a report result as json or csv." + "\n" +
                    "[id] is required. This is id of the report result." + "\n" +
                    "[file] is required. This is local destination for the downloaded file."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      report_result = find_report_result_by_id(args[0])
      return 1 if report_result.nil?

      outfile = args[1]
      outfile = File.expand_path(outfile)
      
      if Dir.exists?(outfile)
        print_red_alert "[file] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exists?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          print_red_alert "[file] is invalid. Directory not found: #{destination_dir}"
          return 1
        end
      end
      if File.exists?(outfile)
        if do_overwrite
          # uhh need to be careful wih the passed filepath here..
          # don't delete, just overwrite.
          # File.delete(outfile)
        else
          print_error Morpheus::Terminal.angry_prompt
          puts_error "[file] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
          # puts_error optparse
          return 1
        end
      end

      @reports_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @reports_interface.dry.export(report_result['id'], outfile, params, report_format)
        return 0
      end
      json_response = @reports_interface.export(report_result['id'], outfile, params, report_format)
      print_green_success "Exported report result #{report_result['id']} to file #{outfile}"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a report result." + "\n" +
                    "[id] is required. This is id of the report result."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      report_result = find_report_result_by_id(args[0])
      return 1 if report_result.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the report result: #{report_result['id']}?")
        return 9, "aborted command"
      end

      @reports_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @reports_interface.dry.destroy(report_result['id'])
        return
      end
      json_response = @reports_interface.destroy(report_result['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Deleted report result #{report_result['id']}"
      #list([])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
      opts.footer = "List report types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      
      @reports_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @reports_interface.dry.types(params)
        return
      end

      json_response = @reports_interface.types(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      

      title = "Morpheus Report Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      report_types = json_response['reportTypes']
      
      if report_types.empty?
        print yellow,"No report types found.",reset,"\n"
      else
        columns = {
          "NAME" => 'name',
          "CODE" => 'code'
        }
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(report_types, columns, options)
        print reset
        if json_response['meta']
          print_results_pagination(json_response)
        else
          print_results_pagination({'meta'=>{'total'=>(report_types.size),'size'=>report_types.size,'max'=>(params['max']||25),'offset'=>(params['offset']||0)}})
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def find_report_result_by_id(id)
    begin
      json_response = @reports_interface.get(id.to_i)
      return json_response['reportResult']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Report Result not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_report_type_by_name_or_code_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_report_type_by_id(val)
    else
      return find_report_type_by_name_or_code(val)
    end
  end

  def find_report_type_by_id(id)
    @all_report_types ||= @reports_interface.list({max: 1000})['reportTypes'] || []
    report_types = @all_report_types.select { |it| id && it['id'] == id.to_i }
    if report_types.empty?
      print_red_alert "Report Type not found by id #{id}"
      return nil
    elsif report_types.size > 1
      print_red_alert "#{report_types.size} report types found by id #{id}"
      rows = report_types.collect do |it|
        {id: it['id'], code: it['code'], name: it['name']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :code, :name], {color:red})
      return nil
    else
      return report_types[0]
    end
  end

  def find_report_type_by_name_or_code(name)
    @all_report_types ||= @reports_interface.list({max: 1000})['reportTypes'] || []
    report_types = @all_report_types.select { |it| name && it['code'] == name || it['name'] == name }
    if report_types.empty?
      print_red_alert "Report Type not found by code #{name}"
      return nil
    elsif report_types.size > 1
      print_red_alert "#{report_types.size} report types found by code #{name}"
      rows = report_types.collect do |it|
        {id: it['id'], code: it['code'], name: it['name']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :code, :name], {color:red})
      return nil
    else
      return report_types[0]
    end
  end

  def format_report_status(report_result, return_color=cyan)
    out = ""
    status_string = report_result['status'].to_s
    if status_string == 'ready'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'requested'
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    elsif status_string == 'generating'
      out << "#{cyan}#{status_string.upcase}#{return_color}"
    elsif status_string == 'failed'
      out << "#{red}#{status_string.upcase}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

end

