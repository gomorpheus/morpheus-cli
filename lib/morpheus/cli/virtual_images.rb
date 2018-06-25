# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

# JD: I don't think a lot of this has ever worked, fix it up.

class Morpheus::Cli::VirtualImages
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :get, :add, :add_file, :remove_file, :update, :remove, :types => :virtual_image_types
  alias_subcommand :details, :get
  set_default_subcommand :list

  # def initialize() 
  # 	# @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
  # end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @virtual_images_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).virtual_images
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-t', '--type IMAGE_TYPE', "Image Type" ) do |val|
        options[:imageType] = val.downcase
      end
      opts.on('--all', "All Images" ) do
        options[:filterType] = 'All'
      end
      opts.on('--user', "User Images" ) do
        options[:filterType] = 'User'
      end
      opts.on('--system', "System Images" ) do
        options[:filterType] = 'System'
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List virtual images."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:imageType]
        params[:imageType] = options[:imageType]
      end
      if options[:filterType]
        params[:filterType] = options[:filterType]
      end
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.get(params)
        return
      end
      json_response = @virtual_images_interface.get(params)

      if options[:json]
        puts as_json(json_response, options, "virtualImages")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "virtualImages")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["virtualImages"], options)
        return 0
      end

      
      images = json_response['virtualImages']
      title = "Morpheus Virtual Images"
      subtitles = []
      if options[:imageType]
        subtitles << "Image Type: #{options[:imageType]}".strip
      end
      if options[:filterType]
        subtitles << "Image Type: #{options[:filterType]}".strip
      end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if images.empty?
        print yellow,"No virtual images found.",reset,"\n"
      else
        rows = images.collect do |image|
          image_type = virtual_image_type_for_name_or_code(image['imageType'])
          image_type_display = image_type ? "#{image_type['name']}" : image['imageType']
          {name: image['name'], id: image['id'], type: image_type_display, source: image['userUploaded'] ? "#{green}UPLOADED#{cyan}" : (image['systemImage'] ? 'SYSTEM' : "#{white}SYNCED#{cyan}"), storage: !image['storageProvider'].nil? ? image['storageProvider']['name'] : 'Default', size: image['rawSize'].nil? ? 'Unknown' : "#{Filesize.from("#{image['rawSize']} B").pretty}"}
        end
        columns = [:id, :name, :type, :storage, :size, :source]
        columns = options[:include_fields] if options[:include_fields]
        print cyan
        print as_pretty_table(rows, columns, options)
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
    options = {}
    show_details = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--details', "Show more details." ) do
        show_details = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a virtual image." + "\n" +
                    "[name] is required. This is the name or id of a virtual image."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    image_name = args[0]
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @virtual_images_interface.dry.get(args[0].to_i)
        else
          print_dry_run @virtual_images_interface.dry.get({name:args[0]})
        end
        return
      end
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?
      # refetch
      json_response = @virtual_images_interface.get(image['id'])
      if options[:json]
        puts as_json(json_response, options, "virtualImage")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "virtualImage")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response["virtualImage"]], options)
        return 0
      end

      image = json_response['virtualImage']
      image_files = json_response['cloudFiles'] || json_response['files']


      image_type = virtual_image_type_for_name_or_code(image['imageType'])
      image_type_display = image_type ? "#{image_type['name']}" : image['imageType']
      print_h1 "Virtual Image Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| image_type_display },
        "Storage" => lambda {|it| !image['storageProvider'].nil? ? image['storageProvider']['name'] : 'Default' }, 
        "Size" => lambda {|it| image['rawSize'].nil? ? 'Unknown' : "#{Filesize.from("#{image['rawSize']} B").pretty}" },
        "Source" => lambda {|it| image['userUploaded'] ? "#{green}UPLOADED#{cyan}" : (image['systemImage'] ? 'SYSTEM' : "#{white}SYNCED#{cyan}") }, 
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      advanced_description_cols = {
        "OS Type" => lambda {|it| it['osType'] ? it['osType']['name'] : "" },
        "Min Memory" => lambda {|it| it['minRam'].to_i != 0 ? Filesize.from("#{it['minRam']} B").pretty : "" },
        "Cloud Init?" => lambda {|it| format_boolean it['osType'] },
        "Install Agent?" => lambda {|it| format_boolean it['osType'] },
        "SSH Username" => lambda {|it| it['sshUsername'] },
        "SSH Password" => lambda {|it| it['sshPassword'] },
        "User Data" => lambda {|it| it['userData'] },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenants" => lambda {|it| format_tenants(it['accounts']) },
        "Auto Join Domain?" => lambda {|it| format_boolean it['isAutoJoinDomain'] },
        "VirtIO Drivers Loaded?" => lambda {|it| format_boolean it['virtioSupported'] },
        "VM Tools Installed?" => lambda {|it| format_boolean it['vmToolsInstalled'] },
        "Force Guest Customization?" => lambda {|it| format_boolean it['isForceCustomization'] },
        "Trial Version" => lambda {|it| format_boolean it['trialVersion'] },
        "Sysprep Enabled?" => lambda {|it| format_boolean it['isSysprep'] },
      }
      if show_details
        description_cols.merge!(advanced_description_cols)
      end
      print_description_list(description_cols, image)

      if image_files
        print_h2 "Files (#{image_files.size})"
        # image_files.each {|image_file|
        #   pretty_filesize = Filesize.from("#{image_file['size']} B").pretty
        #   print cyan,"  =  #{image_file['name']} [#{pretty_filesize}]", "\n"
        # }
        image_file_rows = image_files.collect do |image_file|
          
          {filename: image_file['name'], size: Filesize.from("#{image_file['size']} B").pretty}
        end
        print cyan
        print as_pretty_table(image_file_rows, [:filename, :size])
        # print reset,"\n"
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    image_name = args[0]
    options = {}
    tenants_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          tenants_list = []
        else
          tenants_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a virtual image." + "\n" +
                    "[name] is required. This is the name or id of a virtual image."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end

    connect(options)
    begin
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?

      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['virtualImage'] ||= {}
          payload['virtualImage'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        params = options[:options] || {}
        if params.empty? && tenants_list.nil?
          puts optparse
          option_lines = update_virtual_image_option_types().collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
          puts "\nAvailable Options:\n#{option_lines}\n\n"
          exit 1
        end
        if tenants_list
          params['accounts'] = tenants_list
        end
        payload = {'virtualImage' => params}
      end
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.update(image['id'], payload)
        return
      end
      response = @virtual_images_interface.update(image['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        if !response['success']
          exit 1
        end
      else
        print "\n", cyan, "Virtual Image #{image['name']} updated", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def virtual_image_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.virtual_image_types(params)
        return
      end
      json_response = @virtual_images_interface.virtual_image_types(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        image_types = json_response['virtualImageTypes']
        print_h1 "Morpheus Virtual Image Types"
        if image_types.nil? || image_types.empty?
          print yellow,"No image types currently exist on this appliance. This could be a seed issue.",reset,"\n"
        else
          print cyan
          lb_table_data = image_types.collect do |lb_type|
            {name: lb_type['name'], code: lb_type['code']}
          end
          tp lb_table_data, :name, :code
        end

        print reset,"\n"
      end
                rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    image_type_name = nil
    file_url = nil
    file_name = nil
    tenants_list = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] -t TYPE")
      opts.on( '-t', '--type TYPE', "Virtual Image Type" ) do |val|
        image_type_name = val
      end
      opts.on( '--filename NAME', "Image File Name. Specify a name for the uploaded file." ) do |val|
        file_name = val
      end
      opts.on( '-U', '--url URL', "Image File URL. This can be used instead of uploading local files." ) do |val|
        file_url = val
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          tenants_list = []
        else
          tenants_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Create a virtual image."
    end
    optparse.parse!(args)
    # if args.count < 1
    # 	puts optparse
    # 	exit 1
    # end
    image_name = args[0]
    connect(options)

    # if image_type_name.nil?
    # 	puts "Virtual Image Type must be specified"
    # 	puts optparse
    # 	exit 1
    # end

    if image_name
      options[:options] ||= {}
      options[:options]['name'] ||= image_name
    end

    if image_type_name
      image_type = virtual_image_type_for_name_or_code(image_type_name)
      exit 1 if image_type.nil?
      # options[:options] ||= {}
      # options[:options]['imageType'] ||= image_type['code']
    else
      image_type_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'imageType', 'fieldLabel' => 'Image Type', 'type' => 'select', 'optionSource' => 'virtualImageTypes', 'required' => true, 'description' => 'Select Virtual Image Type.', 'displayOrder' => 2}],options[:options],@api_client,{})
      image_type = virtual_image_type_for_name_or_code(image_type_prompt['imageType'])
    end

    begin
      my_option_types = add_virtual_image_option_types(image_type, !file_url)
      # if options[:no_prompt]
      #   my_option_types.each do |it| 
      #     if it['fieldContext'] == 'virtualImageFiles'
      #       opt['required'] = false
      #     end
      #   end
      # end
      params = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, options[:params])
      params.deep_compact!
      virtual_image_payload = {}.merge(params)
      virtual_image_files = virtual_image_payload.delete('virtualImageFiles')
      virtual_image_payload['imageType'] = image_type['code']
      storage_provider_id = virtual_image_payload.delete('storageProviderId')
      if !storage_provider_id.to_s.empty?
        virtual_image_payload['storageProvider'] = {id: storage_provider_id}
      end
      if tenants_list
        virtual_image_payload['accounts'] = tenants_list
      end
      payload = {virtualImage: virtual_image_payload}

      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.create(payload)
        if file_url
          print_dry_run @virtual_images_interface.dry.upload_by_url(":id", file_url, file_name)
        elsif virtual_image_files && !virtual_image_files.empty?
          virtual_image_files.each do |key, filepath|
            print_dry_run @virtual_images_interface.dry.upload(":id", "(Contents of file #{filepath})")
          end
        end
        return
      end

      json_response = @virtual_images_interface.create(payload)
      virtual_image = json_response['virtualImage']

      if options[:json]
        print JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print "\n", cyan, "Virtual Image #{virtual_image['name']} created successfully", reset, "\n\n"
      end

      # now upload the file, do this in the background maybe?
      if file_url
        unless options[:quiet]
          print cyan, "Uploading file by url #{file_url} ...", reset, "\n"
        end
        upload_json_response = @virtual_images_interface.upload_by_url(virtual_image['id'], file_url, file_name)
        if options[:json]
          print JSON.pretty_generate(upload_json_response)
        end
      elsif virtual_image_files && !virtual_image_files.empty?
        virtual_image_files.each do |key, filepath|
          unless options[:quiet]
            print cyan, "Uploading file (#{key}) #{filepath} ...", reset, "\n"
          end
          image_file = File.new(filepath, 'rb')
          upload_json_response = @virtual_images_interface.upload(virtual_image['id'], image_file, file_name)
          if options[:json]
            print JSON.pretty_generate(upload_json_response)
          end
        end
      else
        puts cyan, "No files uploaded.", reset
      end

      if !options[:json]
        get([virtual_image['id']])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_file(args)
    file_url = nil
    file_name = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [filepath]")
      opts.on('--filename FILENAME', String, "Filename for uploaded file. Derived from [filepath] by default." ) do |val|
        file_name = val
      end
      opts.on( '-U', '--url URL', "Image File URL. This can be used instead of [filepath]" ) do |val|
        file_url = val
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Upload a virtual image file." + "\n" +
                    "[name] is required. This is the name or id of a virtual image." + "\n" +
                    "[filepath] or --url is required. This is location of the virtual image file."
    end
    optparse.parse!(args)
    image_name = args[0]
    filepath = nil
    if file_url
      if args.count < 1
        puts optparse
        exit 1
      end
    else
      if args.count < 2
        puts optparse
        exit 1
      end
      filepath = args[1]
    end

    connect(options)

    begin
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?
      if file_url
        if options[:dry_run]
          print_dry_run @virtual_images_interface.dry.upload_by_url(image['id'], file_url, file_name)
          return
        end
        unless options[:quiet]
          print cyan, "Uploading file by url #{file_url} ...", reset, "\n"
        end
        json_response = @virtual_images_interface.upload_by_url(image['id'], file_url, file_name)
        if options[:json]
          print JSON.pretty_generate(json_response)
        elsif !options[:quiet]
          print "\n", cyan, "Virtual Image #{image['name']} successfully updated.", reset, "\n\n"
          get([image['id']])
        end
      else
        image_file = File.new(filepath, 'rb')
        if options[:dry_run]
          print_dry_run @virtual_images_interface.dry.upload(image['id'], image_file, file_name)
          return
        end
        unless options[:quiet]
          print cyan, "Uploading file #{filepath} ...", reset, "\n"
        end
        json_response = @virtual_images_interface.upload(image['id'], image_file, file_name)
        if options[:json]
          print JSON.pretty_generate(json_response)
        elsif !options[:quiet]
          print "\n", cyan, "Virtual Image #{image['name']} successfully updated.", reset, "\n\n"
          get([image['id']])
        end
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_file(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [filename]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    image_name = args[0]
    filename = args[1]
    connect(options)
    begin
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the virtual image filename #{filename}?")
        exit
      end
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.destroy_file(image['id'], filename)
        return
      end
      json_response = @virtual_images_interface.destroy_file(image['id'], filename)
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        print "\n", cyan, "Virtual Image #{image['name']} filename #{filename} removed", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    image_name = args[0]
    connect(options)
    begin
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the virtual image #{image['name']}?")
        exit
      end
      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.destroy(image['id'])
        return
      end
      json_response = @virtual_images_interface.destroy(image['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
      else
        print "\n", cyan, "Virtual Image #{image['name']} removed", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private
    def find_virtual_image_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_virtual_image_by_id(val)
    else
      return find_virtual_image_by_name(val)
    end
  end

  def find_virtual_image_by_id(id)
    begin
      json_response = @virtual_images_interface.get(id.to_i)
      return json_response['virtualImage']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Virtual Image not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_virtual_image_by_name(name)
    json_results = @virtual_images_interface.get({name: name.to_s})
    if json_results['virtualImages'].empty?
      print_red_alert "Virtual Image not found by name #{name}"
      return nil
    end
    virtual_image = json_results['virtualImages'][0]
    return virtual_image
  end


  def get_available_virtual_image_types(refresh=false)
    if !@available_virtual_image_types || refresh
      @available_virtual_image_types = @virtual_images_interface.virtual_image_types['virtualImageTypes'] #  || []
    end
    return @available_virtual_image_types
  end
    def virtual_image_type_for_name_or_code(name)
    return get_available_virtual_image_types().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
  end

  def add_virtual_image_option_types(image_type = nil, include_file_selection=true)
    
    # todo: make api provide virtualImageType and its optionTypes.
    tmp_option_types = [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      #{'fieldName' => 'imageType', 'fieldLabel' => 'Image Type', 'type' => 'select', 'optionSource' => 'virtualImageTypes', 'required' => true, 'description' => 'Select Virtual Image Type.', 'displayOrder' => 2},
      {'fieldName' => 'osType', 'fieldLabel' => 'OS Type', 'type' => 'select', 'optionSource' => 'osTypes', 'required' => false, 'description' => 'Select OS Type.', 'displayOrder' => 3},
      {'fieldName' => 'minRam', 'fieldLabel' => 'Minimum Memory (MB)', 'type' => 'number', 'required' => false, 'description' => 'Minimum Memory (MB)', 'displayOrder' => 4},
      {'fieldName' => 'isCloudInit', 'fieldLabel' => 'Cloud Init Enabled?', 'type' => 'checkbox', 'required' => false, 'description' => 'Cloud Init Enabled?', 'displayOrder' => 4},
      {'fieldName' => 'installAgent', 'fieldLabel' => 'Install Agent?', 'type' => 'checkbox', 'required' => false, 'description' => 'Install Agent?', 'displayOrder' => 4},
      {'fieldName' => 'sshUsername', 'fieldLabel' => 'SSH Username', 'type' => 'text', 'required' => false, 'description' => 'Enter an SSH Username', 'displayOrder' => 5},
      {'fieldName' => 'sshPassword', 'fieldLabel' => 'SSH Password', 'type' => 'password', 'required' => false, 'description' => 'Enter an SSH Password', 'displayOrder' => 6},
      {'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Storage Provider', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.', 'displayOrder' => 7},
      {'fieldName' => 'userData', 'fieldLabel' => 'Cloud-Init User Data', 'type' => 'textarea', 'required' => false, 'displayOrder' => 10},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions', 'defaultValue' => 'private', 'displayOrder' => 40},
      {'fieldName' => 'isAutoJoinDomain', 'fieldLabel' => 'Auto Join Domain?', 'type' => 'checkbox', 'required' => false, 'description' => 'Auto Join Domain?', 'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'virtioSupported', 'fieldLabel' => 'VirtIO Drivers Loaded?', 'type' => 'checkbox', 'defaultValue' => 'on', 'required' => false, 'description' => 'VirtIO Drivers Loaded?',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'vmToolsInstalled', 'fieldLabel' => 'VM Tools Installed?', 'type' => 'checkbox', 'defaultValue' => 'on', 'required' => false, 'description' => 'VM Tools Installed?',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'isForceCustomization', 'fieldLabel' => 'Force Guest Customization?', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Force Guest Customization?',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'trialVersion', 'fieldLabel' => 'Trial Version', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Trial Version',  'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'isSysprep', 'fieldLabel' => 'Sysprep Enabled?', 'type' => 'checkbox', 'defaultValue' => 'off', 'required' => false, 'description' => 'Sysprep Enabled?',  'category' => 'advanced', 'displayOrder' => 40}      
    ]

    image_type_code = image_type ? image_type['code'] : nil
    if image_type_code
      if image_type_code == 'ami'
        tmp_option_types << {'fieldName' => 'externalId', 'fieldLabel' => 'AMI id', 'type' => 'text', 'required' => false, 'displayOrder' => 10}
        if include_file_selection
          tmp_option_types << {'fieldName' => 'imageFile', 'fieldLabel' => 'Image File', 'type' => 'file', 'required' => false, 'displayOrder' => 10}
        end
      elsif image_type_code == 'vmware' || image_type_code == 'vmdk'
        if include_file_selection
          tmp_option_types << {'fieldContext' => 'virtualImageFiles', 'fieldName' => 'imageFile', 'fieldLabel' => 'OVF File', 'type' => 'file', 'required' => false, 'displayOrder' => 10}
          tmp_option_types << {'fieldContext' => 'virtualImageFiles', 'fieldName' => 'imageDescriptorFile', 'fieldLabel' => 'VMDK File', 'type' => 'file', 'required' => false, 'displayOrder' => 10}
        end
      elsif image_type_code == 'pxe'
        tmp_option_types << {'fieldName' => 'config.menu', 'fieldLabel' => 'Menu', 'type' => 'text', 'required' => false, 'displayOrder' => 10}
        tmp_option_types << {'fieldName' => 'imagePath', 'fieldLabel' => 'Image Path', 'type' => 'text', 'required' => true, 'displayOrder' => 10}
        tmp_option_types.reject! {|opt| ['isCloudInit', 'installAgent', 'sshUsername', 'sshPassword'].include?(opt['fieldName'])}
      else
        if include_file_selection
          tmp_option_types << {'fieldContext' => 'virtualImageFiles', 'fieldName' => 'imageFile', 'fieldLabel' => 'Image File', 'type' => 'file', 'required' => false, 'description' => 'Choose an image file to upload', 'displayOrder' => 10}
        end
      end
    end

    return tmp_option_types
  end

  def update_virtual_image_option_types(image_type = nil)
    list = add_virtual_image_option_types(image_type)
    list.each {|it| it['required'] = false }
    list
  end

  def format_tenants(accounts)
    if accounts && accounts.size > 0
      accounts = accounts.sort {|a,b| a['name'] <=> b['name'] }.uniq {|it| it['id'] }
      account_ids = accounts.collect {|it| it['id'] }
      account_names = accounts.collect {|it| it['name'] }
      "(#{account_ids.join(',')}) #{account_names.join(',')}"
    else
      ""
    end
  end

end
