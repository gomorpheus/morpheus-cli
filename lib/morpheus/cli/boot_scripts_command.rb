require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::BootScriptsCommand
  include Morpheus::Cli::CliCommand

  #set_command_name :'boot-scripts'

  # lives under image-builder domain right now
  set_command_hidden
  def command_name
    "image-builder boot-scripts"
  end

  register_subcommands :list, :get, :add, :update, :remove
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @image_builder_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).image_builder
    @boot_scripts_interface = @image_builder_interface.boot_scripts
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      @boot_scripts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @boot_scripts_interface.dry.list(params)
        return
      end

      json_response = @boot_scripts_interface.list(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      boot_scripts = json_response['bootScripts']
      title = "Morpheus Boot Scripts"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if boot_scripts.empty?
        print cyan,"No boot scripts found.",reset,"\n"
      else
        rows = boot_scripts.collect {|boot_script| 
            row = {
              id: boot_script['id'],
              name: boot_script['fileName']
            }
            row
          }
          columns = [:id, :name]
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[boot-script]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [boot-script]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      @boot_scripts_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @boot_scripts_interface.dry.get(args[0].to_i)
        else
          print_dry_run @boot_scripts_interface.dry.list({name:args[0]})
        end
        return
      end
      boot_script = find_boot_script_by_name_or_id(args[0])
      return 1 if boot_script.nil?
      json_response = {'bootScript' => boot_script}  # skip redundant request
      # json_response = @boot_scripts_interface.get(boot_script['id'])
      boot_script = json_response['bootScript']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      print_h1 "Boot Script Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'fileName',
        # "Description" => 'description',
        # "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        # "Visibility" => lambda {|it| it['visibility'] ? it['visibility'].capitalize() : 'Private' },
      }
      print_description_list(description_cols, boot_script)

      print_h2 "Script"
      print cyan
      puts boot_script['content']
      
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[fileName]")
      build_option_type_options(opts, options, add_boot_script_option_types(false))
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet])
    end
    optparse.parse!(args)
    connect(options)
    begin
      options[:options] ||= {}
      # support [boot-script] as first argument still
      if args[0]
        options[:options]['fileName'] = args[0]
      end

      payload = {
        'bootScript' => {}
      }
      # prompt for Script Content unless --file is passed.
      my_options = add_boot_script_option_types()
      if options[:options]['file']
        my_options = my_options.reject {|it| it['fieldName'] == 'content' }
      # elsif options[:options]['content']
      #   my_options = my_options.reject {|it| it['fieldName'] == 'file' }
      else
        my_options = my_options.reject {|it| it['fieldName'] == 'file' }
      end
      params = Morpheus::Cli::OptionTypes.prompt(my_options, options[:options], @api_client, options[:params])
      script_file = params.delete('file')
      if script_file
        if !File.exists?(script_file)
          print_red_alert "File not found: #{script_file}"
          return 1
        end
        payload['bootScript']['content'] = File.read(script_file)
      end
      payload['bootScript'].merge!(params)
      @boot_scripts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @boot_scripts_interface.dry.create(payload)
        return
      end
      json_response = @boot_scripts_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Added image build #{payload['bootScript']['fileName']}"
        # list([])
        boot_script = json_response['bootScript']
        get([boot_script['id']])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[boot-script] [options]")
      build_option_type_options(opts, options, update_boot_script_option_types(false))
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)

    begin
      boot_script = find_boot_script_by_name_or_id(args[0])

      payload = {
        'bootScript' => {id: boot_script["id"]}
      }

      params = options[:options] || {}
      #puts "parsed params is : #{params.inspect}"
      params = params.select {|k,v| params[k].to_s != "" }
      if params.empty?
        print_red_alert "Specify atleast one option to update"
        puts optparse
        return 1
      end

      # prompt for Script Content unless --file is passed.
      # my_options = add_boot_script_option_types()
      # if options[:options]['file']
      #   my_options = my_options.reject {|it| it['fieldName'] == 'content' }
      # # elsif options[:options]['content']
      # #   my_options = my_options.reject {|it| it['fieldName'] == 'file' }
      # else
      #   my_options = my_options.reject {|it| it['fieldName'] == 'file' }
      # end
      # params = Morpheus::Cli::OptionTypes.prompt(my_options, options[:options], @api_client, options[:params])
      script_file = params.delete('file')
      if script_file
        if !File.exists?(script_file)
          print_red_alert "File not found: #{script_file}"
          return 1
        end
        payload['bootScript']['content'] = File.read(script_file)
      end
      payload['bootScript'].merge!(params)
      @boot_scripts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @boot_scripts_interface.dry.update(boot_script["id"], payload)
        return
      end

      json_response = @boot_scripts_interface.update(boot_script["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated boot script #{boot_script['fileName']}"
        get([boot_script['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[boot-script]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run])
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [boot-script]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      boot_script = find_boot_script_by_name_or_id(args[0])
      return 1 if boot_script.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the boot script: #{boot_script['fileName']}?")
        return 9, "aborted command"
      end
      @boot_scripts_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @boot_scripts_interface.dry.destroy(boot_script['id'])
        return 0
      end
      json_response = @boot_scripts_interface.destroy(boot_script['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed boot script #{boot_script['fileName']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

  def get_available_boot_script_types()
    [{'name' => 'VMware', 'value' => 'vmware'}]
  end

  def add_boot_script_option_types(connected=true)
    [
      {'fieldName' => 'fileName', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this script.'},
      # {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'file', 'fieldLabel' => 'Script File', 'type' => 'file', 'required' => false, 'description' => 'Set script contents to that of a local file.'},
      {'fieldName' => 'content', 'fieldLabel' => 'Script', 'type' => 'code-editor', 'required' => true},
    ]
  end

  def update_boot_script_option_types(connected=true)
    list = add_boot_script_option_types(connected)
    # list = list.reject {|it| ["group"].include? it['fieldName'] }
    list.each {|it| it['required'] = false }
    list
  end

 def find_boot_script_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_boot_script_by_id(val)
    else
      return find_boot_script_by_name(val)
    end
  end

  def find_boot_script_by_id(id)
    begin
      json_response = @boot_scripts_interface.get(id.to_i)
      return json_response['bootScript']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Boot Script not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_boot_script_by_name(name)
    boot_scripts = @boot_scripts_interface.list({name: name.to_s})['bootScripts']
    if boot_scripts.empty?
      print_red_alert "Boot Script not found by name #{name}"
      return nil
    elsif boot_scripts.size > 1
      print_red_alert "#{boot_scripts.size} boot scripts found by name #{name}"
      rows = boot_scripts.collect do |it|
        {id: it['id'], name: it['fileName']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return boot_scripts[0]
    end
  end

end
