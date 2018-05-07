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
    optparse = OptionParser.new do|opts|
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
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
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
        print JSON.pretty_generate(json_response)
      else
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
          print cyan
          print as_pretty_table(rows, columns, options)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
                rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
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
      image = json_response['virtualImage']
      image_files = json_response['cloudFiles'] || json_response['files']

      if options[:json]
        puts JSON.pretty_generate(json_response)
      else
        image_type = virtual_image_type_for_name_or_code(image['imageType'])
        image_type_display = image_type ? "#{image_type['name']}" : image['imageType']
        print_h1 "Virtual Image Details"
        print cyan
        description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| image_type_display },
          # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
        }
        print_description_list(description_cols, image)

        if image_files
          print_h2 "Files"
          image_files.each {|image_file|
            pretty_filesize = Filesize.from("#{image_file['size']} B").pretty
            print cyan,"  =  #{image_file['name']} [#{pretty_filesize}]", "\n"
          }
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # JD: I don't think this has ever worked
  def update(args)
    image_name = args[0]
    options = {}
    account_name = nil
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
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

      params = options[:options] || {}

      if params.empty?
        puts optparse
        option_lines = update_virtual_image_option_types().collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
        puts "\nAvailable Options:\n#{option_lines}\n\n"
        exit 1
      end

      image_payload = {id: image['id']}
      image_payload.merge(params)
      # JD: what can be updated?
      payload = {virtualImage: image_payload}
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
        print "\n", cyan, "Task #{response['task']['name']} updated", reset, "\n\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def virtual_image_types(args)
    options = {}
    optparse = OptionParser.new do|opts|
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
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] -t TYPE")
      opts.on( '-t', '--type TYPE', "Virtual Image Type" ) do |val|
        image_type_name = val
      end
      opts.on( '-U', '--url URL', "Image File URL. This can be used instead of uploading local files." ) do |val|
        file_url = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
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
      virtual_image_payload = {}.merge(params)
      virtual_image_files = virtual_image_payload.delete('virtualImageFiles')
      virtual_image_payload['imageType'] = image_type['code']
      storage_provider_id = virtual_image_payload.delete('storageProviderId')
      if !storage_provider_id.to_s.empty?
        virtual_image_payload['storageProvider'] = {id: storage_provider_id}
      end
      payload = {virtualImage: virtual_image_payload}

      if options[:dry_run]
        print_dry_run @virtual_images_interface.dry.create(payload)
        if file_url
          print_dry_run @virtual_images_interface.dry.upload_by_url(":id", file_url)
        elsif virtual_image_files && !virtual_image_files.empty?
          virtual_image_files.each do |key, filename|
            print_dry_run @virtual_images_interface.dry.upload(":id", "(Contents of file #{filename})")
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
        upload_json_response = @virtual_images_interface.upload_by_url(virtual_image['id'], file_url)
        if options[:json]
          print JSON.pretty_generate(upload_json_response)
        end
      elsif virtual_image_files && !virtual_image_files.empty?
        virtual_image_files.each do |key, filename|
          unless options[:quiet]
            print cyan, "Uploading file (#{key}) #{filename} ...", reset, "\n"
          end
          image_file = File.new(filename, 'rb')
          upload_json_response = @virtual_images_interface.upload(virtual_image['id'], image_file)
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
    image_type_name = nil
    file_url = nil
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [filepath]")
      opts.on( '-U', '--url URL', "Image File URL. This can be used instead of [filepath]" ) do |val|
        file_url = val
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    image_name = args[0]
    filename = nil
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
      filename = args[1]
    end

    connect(options)

    begin
      image = find_virtual_image_by_name_or_id(image_name)
      return 1 if image.nil?
      if file_url
        if options[:dry_run]
          print_dry_run @virtual_images_interface.dry.upload_by_url(image['id'], file_url)
          return
        end
        unless options[:quiet]
          print cyan, "Uploading file by url #{file_url} ...", reset, "\n"
        end
        json_response = @virtual_images_interface.upload_by_url(image['id'], file_url)
        if options[:json]
          print JSON.pretty_generate(json_response)
        elsif !options[:quiet]
          print "\n", cyan, "Virtual Image #{image['name']} successfully updated.", reset, "\n\n"
          get([image['id']])
        end
      else
        image_file = File.new(filename, 'rb')
        if options[:dry_run]
          print_dry_run @virtual_images_interface.dry.upload(image['id'], image_file)
          return
        end
        unless options[:quiet]
          print cyan, "Uploading file #{filename} ...", reset, "\n"
        end
        json_response = @virtual_images_interface.upload(image['id'], image_file)
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
    optparse = OptionParser.new do|opts|
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
    optparse = OptionParser.new do|opts|
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

  def add_virtual_image_option_types(image_type, include_file_selection=true)
    image_type_code = image_type['code']
    # todo: make api provide virtualImageType and its optionTypes.
    tmp_option_types = [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      #{'fieldName' => 'imageType', 'fieldLabel' => 'Image Type', 'type' => 'select', 'optionSource' => 'virtualImageTypes', 'required' => true, 'description' => 'Select Virtual Image Type.', 'displayOrder' => 2},
      {'fieldName' => 'osType', 'fieldLabel' => 'OS Type', 'type' => 'select', 'optionSource' => 'osTypes', 'required' => false, 'description' => 'Select OS Type.', 'displayOrder' => 3},
      {'fieldName' => 'isCloudInit', 'fieldLabel' => 'Cloud Init Enabled?', 'type' => 'checkbox', 'required' => false, 'description' => 'Cloud Init Enabled?', 'displayOrder' => 4},
      {'fieldName' => 'installAgent', 'fieldLabel' => 'Install Agent?', 'type' => 'checkbox', 'required' => false, 'description' => 'Cloud Init Enabled?', 'displayOrder' => 4},
      {'fieldName' => 'sshUsername', 'fieldLabel' => 'SSH Username', 'type' => 'text', 'required' => false, 'description' => 'Enter an SSH Username', 'displayOrder' => 5},
      {'fieldName' => 'sshPassword', 'fieldLabel' => 'SSH Password', 'type' => 'password', 'required' => false, 'description' => 'Enter an SSH Password', 'displayOrder' => 6},
      {'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Storage Provider', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.', 'displayOrder' => 7},
      {'fieldName' => 'userData', 'fieldLabel' => 'Cloud-Init User Data', 'type' => 'textarea', 'required' => false, 'displayOrder' => 10},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions', 'defaultValue' => 'private', 'displayOrder' => 40},
      {'fieldName' => 'isAutoJoinDomain', 'fieldLabel' => 'Auto Join Domain?', 'type' => 'checkbox', 'required' => false, 'description' => 'Cloud Init Enabled?', 'category' => 'advanced', 'displayOrder' => 40},
      {'fieldName' => 'virtioSupported', 'fieldLabel' => 'VirtIO Drivers Loaded?', 'type' => 'checkbox', 'defaultValue' => 'on', 'required' => false, 'description' => 'VirtIO Drivers Loaded?',  'category' => 'advanced', 'displayOrder' => 40}
    ]

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

    return tmp_option_types
  end

  # JD: what can be updated?
  def update_virtual_image_option_types
    []
  end

end
