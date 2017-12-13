require 'fileutils'
require 'json'
require 'yaml'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::ArchivesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper

  set_command_name :archives

  # bucket commands
  # register_subcommands :list_buckets, :get_bucket, :add_bucket, :update_bucket, :remove_bucket
  register_subcommands :'list' => :list_buckets
  register_subcommands :'get' => :get_bucket
  register_subcommands :'add' => :add_bucket
  register_subcommands :'update' => :update_bucket
  register_subcommands :'remove' => :remove_bucket
  register_subcommands :'download-bucket' => :download_bucket_zip
  # file commands
  register_subcommands :'list-files' => :list_files
  register_subcommands :'ls' => :ls
  register_subcommands :'file' => :get_file
  register_subcommands :'file-history' => :file_history
  register_subcommands :'file-links' => :file_links
  # register_subcommands :'history' => :file_history
  register_subcommands :'upload' => :upload_file
  register_subcommands :'download' => :download_file
  register_subcommands :'read' => :read_file
  register_subcommands :'remove-file' => :remove_file
  register_subcommands :'rm' => :remove_file

  # file link commands
  register_subcommands :'add-file-link' => :add_file_link
  # register_subcommands :'get-file-link' => :get_file_link
  register_subcommands :'remove-file-link' => :remove_file_link
  register_subcommands :'download-link' => :download_file_link
  

  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @archive_buckets_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).archive_buckets
    @archive_files_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).archive_files
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
    # @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list_buckets(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "List archive buckets."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "#{command_name} list expects 0 arguments\n#{optparse}"
    end
    connect(options)
    begin
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      if options[:dry_run]
        print_dry_run @archive_buckets_interface.dry.list(params)
        return
      end

      json_response = @archive_buckets_interface.list(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      archive_buckets = json_response['archiveBuckets']
      title = "Morpheus Archive Buckets"
      subtitles = []
      # if group
      #   subtitles << "Group: #{group['name']}".strip
      # end
      # if cloud
      #   subtitles << "Cloud: #{cloud['name']}".strip
      # end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if archive_buckets.empty?
        print cyan,"No archive buckets found.",reset,"\n"
      else
        rows = archive_buckets.collect {|archive_bucket| 
            row = {
              id: archive_bucket['id'],
              name: archive_bucket['name'],
              description: archive_bucket['description'],
              storageProvider: archive_bucket['storageProvider'] ? archive_bucket['storageProvider']['name'] : 'N/A',
              fileCount: archive_bucket['fileCount'],
              # createdBy: archive_bucket['createdBy'] ? archive_bucket['createdBy']['username'] : '',
              size: format_bytes(archive_bucket['rawSize']),
              owner: archive_bucket['owner'] ? archive_bucket['owner']['name'] : '',
              tenants: archive_bucket['accounts'] ? archive_bucket['accounts'].collect {|it| it['name'] }.join(', ') : '',
              visibility: archive_bucket['visibility'] ? archive_bucket['visibility'].capitalize() : '',
              isPublic: archive_bucket['isPublic'] ? 'Yes' : 'No'
            }
            row
          }
          columns = [
            :id, 
            :name, 
            {:storageProvider => {label: 'Storage'.upcase}}, 
            {:fileCount => {label: '# Files'.upcase}}, 
            :size,
            :owner,
            :tenants,
            :visibility,
            {:isPublic => {label: 'Public URL'.upcase}}
          ]
          term_width = current_terminal_width()
          # if term_width > 170
          #   columns += [:cpu, :memory, :storage]
          # end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          print_results_pagination(json_response, {:label => "bucket", :n_label => "buckets"})
          print reset,"\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_bucket(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      build_common_options(opts, options, [:json, :dry_run])
      opts.footer = "Display archive bucket details and files. " +
                    "\nThe [bucket] component of the argument is the name or id of an archive bucket." +
                    "\nThe [:/path] component is optional and can be used to display files under a sub-directory."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} get expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, search_file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @archive_buckets_interface.dry.get(bucket_id.to_i)
        else
          print_dry_run @archive_buckets_interface.dry.list({name:bucket_id})
        end
        return
      end
      archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      return 1 if archive_bucket.nil?
      json_response = {'archiveBucket' => archive_bucket}  # skip redundant request
      # json_response = @archive_buckets_interface.get(archive_bucket['id'])
      archive_bucket = json_response['archiveBucket']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      subtitles = []
      if search_file_path != "/"
        subtitles << "Path: #{search_file_path}"
      end
      print_h1 "Archive Bucket Details", subtitles
      print cyan

      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        # "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
        "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
        "Tenants" => lambda {|it| it['accounts'] ? it['accounts'].collect {|acnt| acnt['name']}.join(', ') : '' },
        "Visibility" => lambda {|it| it['visibility'] ? it['visibility'].capitalize() : '' },
        "Public URL" => lambda {|it| it['isPublic'] ? 'Yes' : 'No' },
        "Storage" => lambda {|it| it['storageProvider'] ? it['storageProvider']['name'] : '' },
        "# Files" => lambda {|it| it['fileCount'] },
        "Size" => lambda {|it| format_bytes(it['rawSize']) },
        "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      }
      print_description_list(description_cols, archive_bucket)

      # show files
      # search_file_path = "/"
      # if args[1]
      #   search_file_path = args[1]
      # end
      # if search_file_path[0].chr != "/"
      #   search_file_path = "/" + search_file_path
      # end
      # print_h2 "Path: #{search_file_path}"
      print "\n"
      archive_files_json_response = @archive_buckets_interface.list_files(archive_bucket['name'], search_file_path)
      archive_files = archive_files_json_response['archiveFiles']
      if archive_files && archive_files.size > 0
        # archive_files.each do |archive_file|
        #   puts " = #{archive_file['name']}"
        # end
        print_archive_files_table(archive_files)
      else
        if search_file_path.empty? || search_file_path == "/"
          puts "This archive bucket has no files."
        else
          puts "No files found for path #{search_file_path}"
        end
      end
      print cyan

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add_bucket(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('--name VALUE', String, "Name") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        options['description'] = val
      end
      opts.on('--storageProvider VALUE', String, "Storage Provider ID") do |val|
        options['storageProvider'] = val.to_s
      end
      opts.on('--payload JSON', String, "JSON Payload") do |val|
        options['payload'] = JSON.parse(val.to_s)
      end
      opts.on('--payload-file FILE', String, "JSON Payload from a local file") do |val|
        payload_file = val.to_s
        options['payload'] = JSON.parse(File.read(payload_file))
      end
      
      opts.on('--visibility [private|public]', String, "Visibility determines if read access is restricted to the specified Tenants (Private) or all tenants (Public).") do |val|
        options['visibility'] = val.to_s
      end
      opts.on('--accounts LIST', String, "Tenant Accounts (comma separated ids)") do |val|
        # uh don't put commas or leading/trailing spaces in script names pl
        options['accounts'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--isPublic [on|off]', String, "Enabling Public URL allows files to be downloaded without any authentication.") do |val|
        options['isPublic'] = (val.to_s == 'on' || val.to_s == 'true')
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet])
      opts.footer = "Create a new archive bucket."
    end
    optparse.parse!(args)
    connect(options)
    begin
      options.merge!(options[:options]) if options[:options] # so -O var= works..

      # use the -g GROUP or active group by default
      # options['group'] ||=  @active_group_id
      
      # support first arg as name instead of --name
      if args[0] && !options['name']
        options['name'] = args[0]
      end

      archive_bucket_payload = prompt_new_archive_bucket(options)
      return 1 if !archive_bucket_payload
      payload = {'archiveBucket' => archive_bucket_payload}

      if options[:dry_run]
        print_dry_run @archive_buckets_interface.dry.create(payload)
        return
      end
      json_response = @archive_buckets_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        new_archive_bucket = json_response['archiveBucket']
        print_green_success "Added archive bucket #{new_archive_bucket['name']}"
        get_bucket([new_archive_bucket['id']])
        # list([])
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update_bucket(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket] [options]")
      opts.on('--name VALUE', String, "Name") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        options['description'] = val
      end
      # storage provider cannot be changed
      # opts.on('--storageProvider VALUE', String, "Storage Provider ID") do |val|
      #   options['storageProvider'] = val.to_s
      # end
      opts.on('--payload JSON', String, "JSON Payload") do |val|
        options['payload'] = JSON.parse(val.to_s)
      end
      opts.on('--payload-file FILE', String, "JSON Payload from a local file") do |val|
        payload_file = val.to_s
        options['payload'] = JSON.parse(File.read(payload_file))
      end
      
      opts.on('--visibility [private|public]', String, "Visibility determines if read access is restricted to the specified Tenants (Private) or all tenants (Public).") do |val|
        options['visibility'] = val.to_s
      end
      opts.on('--accounts LIST', String, "Tenant Accounts (comma separated ids)") do |val|
        # uh don't put commas or leading/trailing spaces in script names pl
        options['accounts'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      end
      opts.on('--isPublic [on|off]', String, "Enabling Public URL allows files to be downloaded without any authentication.") do |val|
        options['isPublic'] = (val.to_s == 'on' || val.to_s == 'true')
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet])
      opts.footer = "Update an existing archive bucket."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)

    begin
      archive_bucket = find_archive_bucket_by_name_or_id(args[0])

      archive_bucket_payload = prompt_edit_archive_bucket(archive_bucket, options)
      return 1 if !archive_bucket_payload
      payload = {'archiveBucket' => archive_bucket_payload}

      if options[:dry_run]
        print_dry_run @archive_buckets_interface.dry.update(archive_bucket["id"], payload)
        return
      end

      json_response = @archive_buckets_interface.update(archive_bucket["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Updated archive bucket #{archive_bucket['name']}"
        get([archive_bucket['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove_bucket(args)
    full_command_string = "#{command_name} remove #{args.join(' ')}".strip
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id = args[0]
    connect(options)
    begin
      # archive_bucket = find_archive_bucket_by_name_or_id(args[0])
      json_response = @archive_buckets_interface.get(bucket_id, {})
      archive_bucket = json_response['archiveBucket']
      is_owner = json_response['isOwner']
      return 1 if archive_bucket.nil?
      if is_owner == false
        print_red_alert "You must be the owner of archive bucket to remove it."
        return 3
      end
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the archive bucket: #{archive_bucket['name']}?")
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @archive_buckets_interface.dry.destroy(archive_bucket['id'], query_params), full_command_string
        return 0
      end
      json_response = @archive_buckets_interface.destroy(archive_bucket['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed archive bucket #{archive_bucket['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def upload_file(args)
    options = {}
    query_params = {}
    do_recursive = false
    ignore_regexp = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[local-file] [bucket:/path]")
      # opts.on('--filename FILEPATH', String, "Remote file path for the file or folder being uploaded, this is an alternative to [remote-file-path]." ) do |val|
      #   options['type'] = val
      # end
      opts.on( '-R', '--recursive', "Upload a directory and all of its files. This must be passed if [local-file] is a directory." ) do
        do_recursive = true
      end
      opts.on('--ignore-files PATTERN', String, "Pattern of files to be ignored when uploading a directory." ) do |val|
        ignore_regexp = /#{Regexp.escape(val)}/
      end
      opts.footer = "Upload a local file or folder to an archive bucket. " +
                    "\nThe first argument [local-file] should be the path of a local file or directory." +
                    "\nThe second argument [bucket:/path] should contain the bucket name." +
                    "\nThe [:/path] component is optional and can be used to specify the destination of the uploaded file or folder." +
                    "\nThe default destination is the same name as the [local-file], under the root bucket directory '/'. " +
                    "\nThis will overwrite any existing remote files that match the destination /path."
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
    end
    optparse.parse!(args)
    
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} upload expects 2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    # validate local file path
    local_file_path = File.expand_path(args[0].squeeze('/'))
    if local_file_path == "" || local_file_path == "/" || local_file_path == "."
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [local-file]\n#{optparse}"
      return 1
    end
    if !File.exists?(local_file_path)
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} bad argument: [local-file]\nFile '#{local_file_path}' was not found.\n#{optparse}"
      return 1
    end

    # validate bucket:/path
    bucket_id, remote_file_path  = parse_bucket_id_and_file_path(args[1])

    # if local_file_path.include?('../') # || options[:yes]
    #   raise_command_error "Sorry, you may not use relative paths in your local filepath."
    # end
    
    # validate bucket name (or id)
    if !bucket_id
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [bucket]\n#{optparse}"
      return 1
    end
    
    # strip leading slash of remote name
    # if remote_file_path[0].chr == "/"
    #   remote_file_path = remote_file_path[1..-1]
    # end

    if remote_file_path.include?('./') # || options[:yes]
      raise_command_error "Sorry, you may not use relative paths in your remote filepath."
    end

    # if !options[:yes]
    scary_local_paths = ["/", "/root", "C:\\"]
    if scary_local_paths.include?(local_file_path)
      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to upload all the files in local directory '#{local_file_path}' !?")
        return 9, "aborted command"
      end
    end
    # end

    connect(options)
    begin
      archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      return 1 if archive_bucket.nil?

      # how many files we dealing with?
      files_to_upload = []
      if File.directory?(local_file_path)
        # upload directory
        if !do_recursive
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "bad argument: '#{local_file_path}' is a directory.  Use -R or --recursive to upload a directory.\n#{optparse}"
          return 1
        end
        found_files = Dir.glob("#{local_file_path}/**/*")
        # note:  api call for directories is not needed
        found_files = found_files.select {|file| File.file?(file) }
        if ignore_regexp
          found_files = found_files.reject {|it| it =~ ignore_regexp} 
        end
        files_to_upload = found_files

        if files_to_upload.size == 0
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "bad argument: Local directory '#{local_file_path}' contains 0 files."
          return 1
        end

        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to upload directory #{local_file_path} (#{files_to_upload.size} files) to #{archive_bucket['name']}:#{remote_file_path}?")
          return 9, "aborted command"
        end

        if !options[:yes]
          if files_to_upload.size > 100
            unless Morpheus::Cli::OptionTypes.confirm("Are you REALLY sure you want to upload #{files_to_upload.size} files ?")
              return 9, "aborted command"
            end
          end
        end

        # local_dirname = File.dirname(local_file_path)
        # local_basename = File.basename(local_file_path)
        upload_file_list = []
        files_to_upload.each do |file|
          destination = file.sub(local_file_path, (remote_file_path || "")).squeeze('/')
          upload_file_list << {file: file, destination: destination}
        end

        if options[:dry_run]
          # print_h1 "DRY RUN"
          print "\n",cyan, bold, "Uploading #{upload_file_list.size} Files...", reset, "\n"
          upload_file_list.each do |obj|
            file, destination = obj[:file], obj[:destination]
            #print cyan,bold, "  - Uploading #{file} to #{bucket_id}:#{destination} DRY RUN", reset, "\n"
            print_dry_run @archive_buckets_interface.dry.upload_file(bucket_id, file, destination)
            print "\n"
          end
          return 0
        end

        print "\n",cyan, bold, "Uploading #{upload_file_list.size} Files...", reset, "\n"
        bad_upload_responses = []
        upload_file_list.each do |obj|
          file, destination = obj[:file], obj[:destination]
          print cyan,bold, "  - Uploading #{file} to #{bucket_id}:#{destination}", reset
          upload_response = @archive_buckets_interface.upload_file(bucket_id, file, destination)
          if upload_response['success']
            print bold," #{green}SUCCESS#{reset}"
          else
            print bold," #{red}ERROR#{reset}"
            if upload_response['msg']
              bad_upload_responses << upload_response
              print " #{upload_response['msg']}#{reset}"
            end
          end
          print "\n"
        end
        if bad_upload_responses.size > 0
          print cyan, bold, "Completed Upload of #{upload_file_list.size} Files. #{red}#{bad_upload_responses.size} Errors!", reset, "\n"
        else
          print cyan, bold, "Completed Upload of #{upload_file_list.size} Files!", reset, "\n"
        end

      else

        # upload file
        if !File.exists?(local_file_path) && !File.file?(local_file_path)
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "#{command_name} bad argument: [local-file]\nFile '#{local_file_path}' was not found.\n#{optparse}"
          return 1
        end

        # local_dirname = File.dirname(local_file_path)
        # local_basename = File.basename(local_file_path)
        
        file = local_file_path
        destination = File.basename(file)
        if remote_file_path[-1].chr == "/"
          # work like `cp`, and place into the directory
          destination = remote_file_path + File.basename(file)
        elsif remote_file_path
          # renaming file
          destination = remote_file_path
        end
        destination = destination.squeeze('/')

        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to upload #{local_file_path} to #{archive_bucket['name']}:#{destination}?")
          return 9, "aborted command"
        end

        if options[:dry_run]
          #print cyan,bold, "  - Uploading #{file} to #{bucket_id}:#{destination} DRY RUN", reset, "\n"
          # print_h1 "DRY RUN"
          print_dry_run @archive_buckets_interface.dry.upload_file(bucket_id, file, destination)
          print "\n"
          return 0
        end
      
        print cyan,bold, "  - Uploading #{file} to #{bucket_id}:#{destination}", reset
        upload_response = @archive_buckets_interface.upload_file(bucket_id, file, destination)
        if upload_response['success']
          print bold," #{green}Success#{reset}"
        else
          print bold," #{red}Error#{reset}"
          if upload_response['msg']
            print " #{upload_response['msg']}#{reset}"
          end
        end
        print "\n"

      end
      #print cyan, bold, "Upload Complete!", reset, "\n"

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_files(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      opts.on('-a', '--all', "Show all files, including subdirectories under the /path.") do
        params[:fullTree] = true
      end
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "List files in an archive bucket. \nInclude [/path] to show files under a directory."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} list-files expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, search_file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      return 1 if archive_bucket.nil?
      [:phrase, :offset, :max, :sort, :direction, :fullTree].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if params[:phrase]
        params[:fullTree] = true # these are not exclusively supported by api yet
      end
      if options[:dry_run]
        print_dry_run @archive_buckets_interface.dry.list_files(bucket_id, search_file_path, params)
        return
      end
      json_response = @archive_buckets_interface.list_files(bucket_id, search_file_path, params)
      archive_files = json_response['archiveFiles']
      # archive_bucket = json_response['archiveBucket']
      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end
      # print_h1 "Archive Files"
      # print_h1 "Archive Files", ["Bucket: [#{archive_bucket['id']}] #{archive_bucket['name']}", "Path: #{search_file_path}"]
      print_h1 "Archive Files", ["#{archive_bucket['name']}:#{search_file_path}"]
      print cyan
      description_cols = {
        "Bucket ID" => 'id',
        "Bucket Name" => 'name',
        #"Path" => lambda {|it| search_file_path }
      }
      #print_description_list(description_cols, archive_bucket)
      #print "\n"
      #print_h2 "Path: #{search_file_path}"
      # print "Directory: #{search_file_path}"
      if archive_files && archive_files.size > 0
        print_archive_files_table(archive_files, {fullTree: params[:fullTree]})
        print_results_pagination(json_response, {:label => "file", :n_label => "files"})
      else
        # puts "No files found for path #{search_file_path}"
        if search_file_path.empty? || search_file_path == "/"
          puts "This archive bucket has no files."
        else
          puts "No files found for path #{search_file_path}"
          return 1
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def ls(args)
    options = {}
    params = {}
    do_one_file_per_line = false
    do_long_format = false
    do_human_bytes = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket/path]")
      opts.on('-a', '--all', "Show all files, including subdirectories under the /path.") do
        params[:fullTree] = true
        do_one_file_per_line = true
      end
      opts.on('-l', '--long', "Lists files in the long format, which contains lots of useful information, e.g. the exact size of the file, the file type, and when it was last modified.") do
        do_long_format = true
        do_one_file_per_line
      end
      opts.on('-H', '--human', "Humanized file sizes. The default is just the number of bytes.") do
        do_human_bytes = true
      end
      opts.on('-1', '--oneline', "One file per line. The default delimiter is a single space.") do
        do_one_file_per_line = true
      end
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "Print filenames for a given archive location.\nPass archive location in the format bucket/path."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} ls expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, search_file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      # archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      # return 1 if archive_bucket.nil?
      [:phrase, :offset, :max, :sort, :direction, :fullTree].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @archive_buckets_interface.dry.list_files(bucket_id, search_file_path, params)
        return 0
      end
      json_response = @archive_buckets_interface.list_files(bucket_id, search_file_path, params)
      if options[:json]
        puts as_json(json_response, options)
        # no files is an error condition for this command
        if !json_response['archiveFiles'] || json_response['archiveFiles'].size == 0
          return 1
        end
        return 0
      end
      archive_bucket = json_response['archiveBucket'] # yep, this is returned too
      archive_files = json_response['archiveFiles']
      # archive_bucket = json_response['archiveBucket']
      # print_h2 "Directory: #{search_file_path}"
      # print "Directory: #{search_file_path}"
      if archive_files && archive_files.size > 0
        if do_long_format
          # ls long format
          # owner groups filesize type filename
          now = Time.now
          archive_files.each do |archive_file|
            # -rw-r--r--    1 jdickson  staff   1361 Oct 23 08:00 voltron_2.10.log
            file_color = cyan # reset
            if archive_file['isDirectory']
              file_color = blue
            end
            file_info = []
            # Number of links
            # file_info << file["linkCount"].to_i + 1
            # Owner
            owner_str = ""
            if archive_file['owner']
              owner_str = archive_file['owner']['name']
            elsif archive_bucket['owner']
              owner_str = archive_bucket['owner']['name']
            else
              owner_str = "noone"
            end
            file_info << truncate_string(owner_str, 15).ljust(15, " ")
            # Group (Tenants)
            groups_str = ""
            if archive_file['visibility'] == 'public'
              # this is confusing because of Public URL (isPublic) setting
              groups_str = "public"
            else
              if archive_file['accounts'].instance_of?(Array) && archive_file['accounts'].size > 0
                # groups_str = archive_file['accounts'].collect {|it| it['name'] }.join(',')
                groups_str = (archive_file['accounts'].size == 1) ? "#{archive_file['accounts'][0]['name']}" : "#{archive_file['accounts'].size} tenants"
              elsif archive_bucket['accounts'].instance_of?(Array) && archive_bucket['accounts'].size > 0
                # groups_str = archive_bucket['accounts'].collect {|it| it['name'] }.join(',')
                groups_str = (archive_bucket['accounts'].size == 1) ? "#{archive_bucket['accounts'][0]['name']}" : "#{archive_bucket['accounts'].size} tenants"
              else
                groups_str = owner_str
              end
            end
            groups_str = 
            file_info << truncate_string(groups_str, 15).ljust(15, " ")
            # File Type
            content_type = archive_file['contentType'].to_s
            if archive_file['isDirectory']
              content_type = "directory"
            else
              content_type = archive_file['contentType'].to_s
            end
            file_info << content_type.ljust(25, " ")
            filesize_str = ""
            if do_human_bytes
              # filesize_str = format_bytes(archive_file['rawSize'])
              filesize_str = format_bytes_short(archive_file['rawSize'])
            else
              filesize_str = archive_file['rawSize'].to_i.to_s
            end
            # file_info << filesize_str.ljust(12, " ")
            file_info << filesize_str.ljust(7, " ")
            mtime = ""
            last_updated = parse_time(archive_file['lastUpdated'])
            if last_updated
              if last_updated.year == now.year
                mtime = format_local_dt(last_updated, {format: "%b %e %H:%M"})
              else
                mtime = format_local_dt(last_updated, {format: "%b %e %Y"})
              end
            end
            file_info << mtime # .ljust(21, " ")
            if params[:fullTree]
              file_info << file_color + archive_file["filePath"].to_s + cyan
            else
              file_info << file_color + archive_file["name"].to_s + cyan
            end
            print cyan, file_info.join("  "), reset, "\n"
          end
        else
          file_names = archive_files.collect do |archive_file|
            file_color = cyan # reset
            if archive_file['isDirectory']
              file_color = blue
            end
            if params[:fullTree]
              file_color + archive_file["filePath"].to_s + reset
            else
              file_color + archive_file["name"].to_s + reset
            end
          end
          if do_one_file_per_line
            print file_names.join("\n")
          else
            print file_names.join(" ")
          end
          print "\n"
        end
      else
        print_error yellow, "No files found for path: #{search_file_path}", reset, "\n"
        return 1
      end
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get_file(args)
    full_command_string = "#{command_name} get-file #{args.join(' ')}".strip
    options = {}
    max_links = 10
    max_history = 10
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      opts.on('-L', '--all-links', "Display all links instead of only 10." ) do
        max_links = 10000
      end
      opts.on('-H', '--all-history', "Display all history instead of only 10." ) do
        max_history = 10000
      end
      build_common_options(opts, options, [:json, :dry_run])
      opts.footer = "Get details about an archive file.\n" + 
                    "[bucket:/path] is required. This is the name of the bucket and /path the file or folder to be fetched." + "\n" +
                    "[id] can be passed instead of [bucket:/path]. This is the numeric File ID."
    end
    optparse.parse!(args)
    # consider only allowing args.count == 1 here in the format [bucket:/path]
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} get-file expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    file_id = nil
    bucket_id = nil
    file_path = nil
    # allow id in place of bucket:path
    if args[0].to_s =~ /\A\d{1,}\Z/
      file_id = args[0]
    else
      bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
    end

    connect(options)
    begin
      # archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      # return 1 if archive_bucket.nil?
      params = {}
      if options[:dry_run]
        if file_id
          print_dry_run @archive_files_interface.dry.get(file_id, params), full_command_string
        else
          print_dry_run @archive_buckets_interface.dry.list_files(bucket_id, file_path, params), full_command_string
        end
        return 0
      end
      archive_file = nil
      json_response = nil
      if !file_id
        archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
        return 1 if archive_file.nil?
        file_id = archive_file['id']
      end
      # archive_file = find_archive_file_by_id(file_id)
      json_response = @archive_files_interface.get(file_id, params)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      archive_file = json_response['archiveFile']
      archive_logs = json_response['archiveLogs']
      is_owner = json_response['isOwner']
      if !bucket_id && archive_file["archiveBucket"]
        bucket_id = archive_file["archiveBucket"]["name"]
      end

      print_h1 "Archive File Details"
      print cyan
      description_cols = {
        "File ID" => 'id',
        "Bucket" => lambda {|it| bucket_id },
        "File Path" => lambda {|it| it['filePath'] },
        "Type" => lambda {|it| it['isDirectory'] ? 'directory' : (it['contentType']) },
        "Size" => lambda {|it| format_bytes(it['rawSize']) },
        "Downloads" => lambda {|it| it['downloadCount'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Last Modified" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, archive_file)
      
      # print "\n"
      
      
      print_h2 "Download URLs"
      private_download_url = "#{@appliance_url}/api/archives/download/#{URI.escape(bucket_id)}" + "/#{URI.escape(archive_file['filePath'])}".squeeze('/')
      public_download_url = nil
      if archive_file['archiveBucket'] && archive_file['archiveBucket']['isPublic']
        public_download_url = "#{@appliance_url}/public-archives/download/#{URI.escape(bucket_id)}" + "/#{URI.escape(archive_file['filePath'])}".squeeze('/')
      end
      print cyan
      puts "Private URL: #{private_download_url}"
      if public_download_url
        puts " Public URL: #{public_download_url}"
      end

      do_show_links = is_owner
      if do_show_links
        links_json_response = @archive_files_interface.list_links(archive_file['id'], {max: max_links})
        archive_file_links = links_json_response['archiveFileLinks']
        if archive_file_links && archive_file_links.size > 0
          print_h2 "Links"
          print_archive_file_links_table(archive_file_links)
          print_results_pagination(links_json_response, {:label => "link", :n_label => "links"})
        else
          print_h2 "File Links"
          puts "No links found"
        end
      end
      # print "\n"
      do_show_history = is_owner
      if do_show_history
        history_json_response = @archive_files_interface.history(archive_file['id'], {max: max_history})
        archive_logs =         history_json_response['archiveLogs']
        print_h2 "History"
        if archive_logs && archive_logs.size > 0
          print_archive_logs_table(archive_logs, {exclude:[:bucket]})
          print_results_pagination(history_json_response, {:label => "history record", :n_label => "history records"})
        else
          puts "No history found"
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  # Use upload file bucket:/path
  # def add_file(args)
  #   raise "not yet implemented"
  # end

  def remove_file(args)
    options = {}
    query_params = {}
    do_recursive = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      opts.on( '-R', '--recursive', "Delete a directory and all of its files. This must be passed if specifying a directory." ) do
        do_recursive = true
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run])
      opts.footer = "Delete an archive file or directory."
    end
    optparse.parse!(args)
    # consider only allowing args.count == 1 here in the format [bucket:/path]
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove-file expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      
      archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      return 1 if archive_file.nil?
      if archive_file['isDirectory']
        if !do_recursive
          print_error Morpheus::Terminal.angry_prompt
          puts_error  "bad argument: '#{file_path}' is a directory.  Use -R or --recursive to delete a directory.\n#{optparse}"
          return 1
        end
        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the archive directory: #{args[0]}?")
          return 9, "aborted command"
        end
      else
        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the archive file: #{args[0]}?")
          return 9, "aborted command"
        end
      end
      
      if options[:dry_run]
        print_dry_run @archive_files_interface.dry.destroy(archive_file['id'], query_params)
        return 0
      end
      json_response = @archive_files_interface.destroy(archive_file['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed archive file #{args[0]}"
      end
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end

  end

  def file_history(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "List history log events for an archive file."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} file-history expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      # todo: only 1 api call needed here.
      # archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      # return 1 if archive_bucket.nil?
      archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      return 1 if archive_file.nil?
      # ok, load history
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @archive_files_interface.dry.history(archive_file['id'], params)
        return
      end
      json_response = @archive_files_interface.history(archive_file['id'], params)
      archive_logs = json_response['archiveLogs']

      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end

      print_h1 "Archive File History", ["#{bucket_id}:#{file_path}"]
      # print cyan
      # description_cols = {
      #   "File ID" => 'id',
      #   "Bucket" => lambda {|it| bucket_id },
      #   "File Path" => lambda {|it| file_path }
      # }
      # print_description_list(description_cols, archive_file)
      # print "\n"
      # print_h2 "History"
      if archive_logs && archive_logs.size > 0
        print_archive_logs_table(archive_logs)
        print_results_pagination(json_response, {:label => "history record", :n_label => "history records"})
      else
        puts "No history found"
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def file_links(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "List links for an archive file."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} file-history expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      # todo: only 1 api call needed here.
      # archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      # return 1 if archive_bucket.nil?
      archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      return 1 if archive_file.nil?
      # ok, load links
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @archive_files_interface.dry.list_links(archive_file['id'], params)
        return
      end
      json_response = @archive_files_interface.list_links(archive_file['id'], params)
      archive_file_links = json_response['archiveFileLinks']

      if options[:json]
        print JSON.pretty_generate(json_response)
        return
      end

      print_h1 "Archive File Links", ["#{bucket_id}:#{file_path}"]
      # print_h1 "Archive File"
      # print cyan
      # description_cols = {
      #   "File ID" => 'id',
      #   "Bucket" => lambda {|it| bucket_id },
      #   "File Path" => lambda {|it| file_path }
      # }
      # print_description_list(description_cols, archive_file)
      # print "\n"
      # print_h2 "Links"
      if archive_file_links && archive_file_links.size > 0
        print_archive_file_links_table(archive_file_links)
        print_results_pagination(json_response, {:label => "link", :n_label => "links"})
      else
        puts "No history found"
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def download_file(args)
    full_command_string = "#{command_name} download #{args.join(' ')}".strip
    options = {}
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    use_public_url = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path] [local-file]")
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        do_overwrite = true
        # do_mkdir = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        do_mkdir = true
      end
      opts.on( '-p', '--public', "Use Public Download URL instead of Private. The file must be in a public archives." ) do
        use_public_url = true
        # do_mkdir = true
      end
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "Download an archive file or directory.\n" + 
                    "[bucket:/path] is required. This is the name of the bucket and /path the file or folder to be downloaded.\n" +
                    "[local-file] is required. This is the full local filepath for the downloaded file.\n" +
                    "Directories will be downloaded as a .zip file, so you'll want to specify a [local-file] with a .zip extension."
    end
    optparse.parse!(args)
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} download expects 2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
      # just make 1 api call for now
      # archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      # return 1 if archive_file.nil?
      full_file_path = "#{bucket_id}/#{file_path}".squeeze('/')
      # full_file_path = args[0]
      # end download destination with a slash to use the local file basename
      outfile = args[1]
      # if outfile[-1] == "/" || outfile[-1] == "\\"
      #   outfile = File.join(outfile, File.basename(full_file_path))
      # end
      outfile = File.expand_path(outfile)
      if Dir.exists?(outfile)
        outfile = File.join(outfile, File.basename(full_file_path))
      end
      if Dir.exists?(outfile)
        print_red_alert "[local-file] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exists?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          print_red_alert "[local-file] is invalid. Directory not found: #{destination_dir}"
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
          puts_error "[local-file] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
          # puts_error optparse
          return 1
        end
      end
      begin
        if options[:dry_run]
          # print_dry_run @archive_files_interface.dry.download_file_by_path(full_file_path), full_command_string
          if use_public_url
            print_dry_run @archive_files_interface.dry.download_file_by_path_chunked(full_file_path, outfile), full_command_string
          else
            print_dry_run @archive_files_interface.dry.download_public_file_by_path_chunked(full_file_path, outfile), full_command_string
          end
          return 1
        end
        if !options[:quiet]
          print cyan + "Downloading archive file #{bucket_id}:#{file_path} to #{outfile} ... "
        end
        # file_response = @archive_files_interface.download_file_by_path(full_file_path)
        # File.write(outfile, file_response.body)
        # err, maybe write to a random tmp file, then mv to outfile
        # currently, whatever the response is, it's written to the outfile. eg. 404 html
        http_response = nil
        if use_public_url
          http_response = @archive_files_interface.download_public_file_by_path_chunked(full_file_path, outfile)
        else
          http_response = @archive_files_interface.download_file_by_path_chunked(full_file_path, outfile)
        end

        # FileUtils.chmod(0600, outfile)
        success = http_response.code.to_i == 200
        if success
          if !options[:quiet]
            print green + "SUCCESS" + reset + "\n"
          end
          return 0
        else
          if !options[:quiet]
            print red + "ERROR" + reset + " HTTP #{http_response.code}" + "\n"
          end
          # F it, just remove a bad result
          if File.exists?(outfile) && File.file?(outfile)
            Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
            File.delete(outfile)
          end
          if options[:debug]
            puts_error http_response.inspect
          end
          return 1
        end
      rescue RestClient::Exception => e
        # this is not reached
        if e.response && e.response.code == 404
          print_red_alert "Archive file not found by path #{full_file_path}"
          return nil
        else
          raise e
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
    
  end

  def read_file(args)
    full_command_string = "archives read #{args.join(' ')}".strip
    options = {}
    outfile = nil
    do_overwrite = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      build_common_options(opts, options, [:auto_confirm, :dry_run])
      opts.footer = "Print the contents of an archive file.\n" + 
                    "[bucket:/path] is required. This is the name of the bucket and /path the file or folder to be downloaded.\n" +
                    "Confirmation is needed if the specified file is more than 1KB.\n" +
                    "This confirmation can be skipped with the -y option."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} read expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
      archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      return 1 if archive_file.nil?
      full_file_path = "#{bucket_id}/#{file_path}".squeeze('/')
      if options[:dry_run]
        print_dry_run @archive_files_interface.dry.download_file_by_path(full_file_path), full_command_string
        return 1
      end
      if archive_file['rawSize'].to_i > 1024
        pretty_size = format_bytes(archive_file['rawSize'])
        unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to print the contents of this file (#{pretty_size}) ?")
          return 9, "aborted command"
        end
      end
      file_response = @archive_files_interface.download_file_by_path(full_file_path)
      puts file_response.body.to_s
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
    
  end

  def add_file_link(args)
    options = {}
    expiration_seconds = 20*60 # default expiration is 20 minutes
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path]")
      opts.on('-e', '--expire SECONDS', "The time to live for this link. The default is 1200 (20 minutes). A value less than 1 means never expire.") do |val|
        expiration_seconds = val.to_i
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet])
      opts.footer = "Create a public link to a file.\n" + 
                    "[bucket:/path] is required. This is the name of the bucket and /path the file or folder to be fetched."
    end
    optparse.parse!(args)
    # consider only allowing args.count == 1 here in the format [bucket:/path]
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add-file-link expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      return 1 if archive_file.nil?

      params = {}
      if expiration_seconds.to_i > 0
        params['expireSeconds'] = expiration_seconds.to_i
      end
      if options[:dry_run]
        print_dry_run @archive_files_interface.dry.create_file_link(archive_file['id'], params)
        return
      end
      json_response = @archive_files_interface.create_file_link(archive_file['id'], params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        return 0
      elsif !options[:quiet]
        print_green_success "Created archive file link #{bucket_id}:/#{archive_file['filePath']} token: #{json_response['secretAccessKey']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove_file_link(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket:/path] [token]")
      build_common_options(opts, options, [:auto_confirm, :dry_run, :quiet])
      opts.footer = "Delete a public link to a file.\n" + 
                    "[bucket:/path] is required. This is the name of the bucket and /path the file or folder to be fetched." +
                    "[token] is required. This is the secret access key that identifies the link."
    end
    optparse.parse!(args)
    # consider only allowing args.count == 1 here in the format [bucket:/path]
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove-file-link expects 2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    bucket_id, file_path  = parse_bucket_id_and_file_path(args[0])
    connect(options)
    begin
      archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      return 1 if archive_file.nil?
      link_id = nil
      secret_access_key = args[1]
      secret_access_key = secret_access_key.sub('/public-archives/link?s=', '')
      # find the int id via token...
      links_json_response = @archive_files_interface.list_links(archive_file['id'], {s: secret_access_key})
      if links_json_response['archiveFileLinks'] && links_json_response['archiveFileLinks'][0]
        link_id = links_json_response['archiveFileLinks'][0]['id']
      end
      if !link_id
        print_red_alert "Archive file link not found for #{bucket_id}:/#{archive_file['filePath']} token: #{secret_access_key}"
        return 1
      end
      params = {}
      if options[:dry_run]
        print_dry_run @archive_files_interface.dry.destroy_file_link(archive_file['id'], link_id, params)
        return
      end
      json_response = @archive_files_interface.destroy_file_link(archive_file['id'], link_id, params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        return 0
      elsif !options[:quiet]
        print_green_success "Deleted archive file link #{bucket_id}:/#{archive_file['filePath']} token: #{secret_access_key}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def download_file_link(args)
    full_command_string = "archives download-link #{args.join(' ')}".strip
    options = {}
    outfile = nil
    do_overwrite = false
    dor_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[link-key] [local-file]")
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        do_overwrite = true
        # do_mkdir = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        do_mkdir = true
      end
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "Download an archive file link.\n" + 
                    "[link-key] is required. This is the secret access key for the archive file link.\n" +
                    "[local-file] is required. This is the full local filepath for the downloaded file."
    end
    optparse.parse!(args)
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} download-link expects 2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      link_key = args[0]
      # archive_file_link = find_archive_file_link_by_key(link_key)
      # just make 1 api call for now
      # archive_file = find_archive_file_by_bucket_and_path(bucket_id, file_path)
      # return 1 if archive_file.nil?
      full_file_path = "#{bucket_id}/#{file_path}".squeeze('/')
      # full_file_path = args[0]
      outfile = File.expand_path(args[1])
      # [local-file] must include the full file name when downloading a link
      # if Dir.exists?(outfile)
      #   outfile = File.join(outfile, File.basename(archive_file['name']))
      # end
      if Dir.exists?(outfile)
        print_red_alert "[local-file] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exists?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          print_red_alert "[local-file] is invalid. Directory not found: #{destination_dir}"
          return 1
        end
      end
      if File.exists?(outfile)
        if do_overwrite
          # uhh need to be careful wih the passed filepath here..
          # don't delete, just overwrite.
          # File.delete(outfile)
        else
          print_red_alert "[local-file] is invalid. File already exists: #{outfile}"
          # print_error Morpheus::Terminal.angry_prompt
          # puts_error  "[local-file] is invalid. File already exists: #{outfile}\n#{optparse}"
          puts_error "Use -f to overwrite the existing file."
          # puts_error optparse
          return 1
        end
      end

      if options[:dry_run]
        # print_dry_run @archive_files_interface.dry.download_file_by_path(full_file_path), full_command_string
        print_dry_run @archive_files_interface.dry.download_file_by_link_chunked(link_key, outfile), full_command_string
        return 1
      end
      if !options[:quiet]
        print cyan + "Downloading archive file link #{link_key} to #{outfile} ... "
      end
      # file_response = @archive_files_interface.download_file_by_path(full_file_path)
      # File.write(outfile, file_response.body)
      # err, maybe write to a random tmp file, then mv to outfile
      # currently, whatever the response is, it's written to the outfile. eg. 404 html
      http_response = @archive_files_interface.download_file_by_link_chunked(link_key, outfile)

      # FileUtils.chmod(0600, outfile)
      success = http_response.code.to_i == 200
      if success
        if !options[:quiet]
          print green + "SUCCESS" + reset + "\n"
        end
        return 0
      else
        if !options[:quiet]
          print red + "ERROR" + reset + " HTTP #{http_response.code}" + "\n"
        end
        # F it, just remove a bad result
        if File.exists?(outfile) && File.file?(outfile)
          Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
          File.delete(outfile)
        end
        if options[:debug]
          puts_error http_response.inspect
        end
        return 1
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
    
  end

  def download_bucket_zip(args)
    full_command_string = "#{command_name} download-bucket #{args.join(' ')}".strip
    options = {}
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    use_public_url = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[bucket] [local-file]")
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        do_overwrite = true
        # do_mkdir = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        do_mkdir = true
      end
      # api endpoint needed still for public bucket.zip
      # opts.on( '-p', '--public', "Use Public Download URL instead of Private. The bucket must be have Public URL enabled." ) do
      #   use_public_url = true
      #   # do_mkdir = true
      # end
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "Download an entire archive bucket as a .zip file.\n" + 
                    "[bucket] is required. This is the name of the bucket.\n" +
                    "[local-file] is required. This is the full local filepath for the downloaded file.\n" +
                    "Buckets are be downloaded as a .zip file, so you'll want to specify a [local-file] with a .zip extension."
    end
    optparse.parse!(args)
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} download-bucket expects 2 arguments and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      bucket_id = args[0].to_s
      archive_bucket = find_archive_bucket_by_name_or_id(bucket_id)
      return 1 if archive_bucket.nil?
      
      outfile = args[1]
      # if outfile[-1] == "/" || outfile[-1] == "\\"
      #   outfile = File.join(outfile, archive_bucket['name'].to_s) + ".zip"
      # end
      outfile = File.expand_path(outfile)
      if Dir.exists?(outfile)
        outfile = File.join(outfile, archive_bucket['name'].to_s) + ".zip"
      end
      if Dir.exists?(outfile)
        print_red_alert "[local-file] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      # always a .zip
      if outfile[-4..-1] != ".zip"
        outfile << ".zip"
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exists?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          print_red_alert "[local-file] is invalid. Directory not found: #{destination_dir}"
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
          puts_error "[local-file] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
          # puts_error optparse
          return 1
        end
      end

      if options[:dry_run]
        print_dry_run @archive_buckets_interface.dry.download_bucket_zip_chunked(bucket_id, outfile), full_command_string
        return 1
      end
      if !options[:quiet]
        print cyan + "Downloading archive bucket #{bucket_id} to #{outfile} ... "
      end

      http_response = @archive_buckets_interface.download_bucket_zip_chunked(bucket_id, outfile)

      # FileUtils.chmod(0600, outfile)
      success = http_response.code.to_i == 200
      if success
        if !options[:quiet]
          print green + "SUCCESS" + reset + "\n"
        end
        return 0
      else
        if !options[:quiet]
          print red + "ERROR" + reset + " HTTP #{http_response.code}" + "\n"
        end
        # F it, just remove a bad result
        if File.exists?(outfile) && File.file?(outfile)
          Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
          File.delete(outfile)
        end
        if options[:debug]
          puts_error http_response.inspect
        end
        return 1
      end
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

  def find_archive_bucket_by_name_or_id(val)
    return find_archive_bucket_by_id(val)
    # if val.to_s =~ /\A\d{1,}\Z/
    #   return find_archive_bucket_by_id(val)
    # else
    #   return find_archive_bucket_by_name(val)
    # end
  end

  def find_archive_bucket_by_id(id)
    begin
      # this is typically passed as name, the api supports either name or id
      json_response = @archive_buckets_interface.get(id.to_s)
      archive_bucket = json_response['archiveBucket']
      archive_bucket['isOwner'] = !!json_response['isOwner']
      return archive_bucket
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Archive bucket not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_archive_bucket_by_name(name)
    archive_buckets = @archive_buckets_interface.list({name: name.to_s})['archiveBuckets']
    if archive_buckets.empty?
      print_red_alert "Archive bucket not found by name #{name}"
      return nil
    elsif archive_buckets.size > 1
      print_red_alert "#{archive_buckets.size} archive buckets found by name #{name}"
      # print_archive_buckets_table(archive_buckets, {color: red})
      rows = archive_buckets.collect do |it|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      return archive_buckets[0]
    end
  end

   def find_archive_file_by_id(id)
    begin
      json_response = @archive_files_interface.get(id.to_s)
      return json_response['archiveFile']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Archive file not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_archive_file_by_bucket_and_path(bucket_id, file_path)
    if file_path.to_s.empty? || file_path.to_s.strip == "/"
      print_red_alert "Archive file not found for bucket: '#{bucket_id}' file: (blank)"
      return nil
    end
    # chomp leading and trailing slashes, the api isn't doin this right now.
    if file_path.size > 1 && file_path[-1] == "/"
      file_path = file_path[0..-2]
    end
    if file_path[0] && file_path[0].chr == "/"
      file_path = file_path[1..-1]
    end
    # ok, find the file id by searching /archives/buckets/$bucketId/files/$filePath
    json_response = @archive_buckets_interface.list_files(bucket_id, file_path)
    # json_response = @archive_buckets_interface.list_files(bucket_id, "/", {phrase: file_path})
    # json_response = @archive_buckets_interface.list_files(bucket_id, "/", {absoluteFilePath: file_path})
    # puts "find_archive_file() json_response is: ", JSON.pretty_generate(json_response)
    archive_file = nil
    archive_files = json_response['archiveFiles']
    # silly hack, not needed while using ?absoluteFilePath=
    if json_response['parentDirectory'] && json_response['parentDirectory']['filePath'] == file_path
      archive_file = json_response['parentDirectory']
    else
      archive_file = archive_files[0]
    end
    if archive_file.nil?
      print_red_alert "Archive file not found for bucket: '#{bucket_id}' file: '#{file_path}'"
      return nil
    end
    return archive_file
  end

  # def find_group_by_name(name)
  #   group_results = @groups_interface.get(name)
  #   if group_results['groups'].empty?
  #     print_red_alert "Group not found by name #{name}"
  #     return nil
  #   end
  #   return group_results['groups'][0]
  # end

  # def find_cloud_by_name(group_id, name)
  #   option_results = @options_interface.options_for_source('clouds',{groupId: group_id})
  #   match = option_results['data'].find { |grp| grp['value'].to_s == name.to_s || grp['name'].downcase == name.downcase}
  #   if match.nil?
  #     print_red_alert "Cloud not found by name #{name}"
  #     return nil
  #   else
  #     return match['value']
  #   end
  # end


  def format_archive_bucket_full_status(archive_bucket, return_color=cyan)
    out = ""
    if archive_bucket['lastResult']
      out << format_archive_bucket_execution_status(archive_bucket['lastResult'])
    else
      out << ""
    end
    out
  end

  def format_archive_bucket_status(archive_bucket, return_color=cyan)
    out = ""
    if archive_bucket['lastResult']
      out << format_archive_bucket_execution_status(archive_bucket['lastResult'])
    else
      out << ""
    end
    out
  end

  def format_archive_bucket_execution_status(archive_bucket_execution, return_color=cyan)
    out = ""
    status_string = archive_bucket_execution['status']
    if status_string == 'running'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'success'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'failed'
      out <<  "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'pending'
      out <<  "#{white}#{status_string.upcase}#{return_color}"
    elsif status_string
      out <<  "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out <<  ""
    end
    out
  end

  def format_archive_bucket_execution_result(archive_bucket_execution, return_color=cyan)
    out = ""
    status_string = archive_bucket_execution['status']
    if status_string == 'running' # || status_string == 'pending'
      out << generate_usage_bar(archive_bucket_execution['statusPercent'], 100, {max_bars: 10})
      out << return_color if return_color
      out << " - #{archive_bucket_execution['statusMessage']}"
    elsif archive_bucket_execution['statusMessage']
      out << "#{archive_bucket_execution['statusMessage']}"
    end
    if archive_bucket_execution['errorMessage']
      out << " - #{red}#{archive_bucket_execution['errorMessage']}#{return_color}"
    end
    out
  end

  # def get_available_boot_scripts()
  #   boot_scripts_dropdown = []
  #   scripts = @boot_scripts_interface.list({max:1000})['bootScripts']
  #   scripts.each do |it| 
  #     boot_scripts_dropdown << {'name'=>it['fileName'],'value'=>it['id']}
  #   end
  #   boot_scripts_dropdown << {'name'=>'Custom','value'=> 'custom'}
  #   return boot_scripts_dropdown
  # end

  def get_available_boot_scripts(refresh=false)
    if !@available_boot_scripts || refresh
      # option_results = options_interface.options_for_source('bootScripts',{})['data']
      boot_scripts_dropdown = []
      scripts = @boot_scripts_interface.list({max:1000})['bootScripts']
      scripts.each do |it| 
        boot_scripts_dropdown << {'name'=>it['fileName'],'value'=>it['id'],'id'=>it['id']}
      end
      boot_scripts_dropdown << {'name'=>'Custom','value'=> 'custom','id'=> 'custom'}
      @available_boot_scripts = boot_scripts_dropdown
    end
    #puts "available_boot_scripts() rtn: #{@available_boot_scripts.inspect}"
    return @available_boot_scripts
  end

  def find_boot_script(val)
    if val.nil? || val.to_s.empty?
      return nil
    else
      return get_available_boot_scripts().find { |it| 
        (it['id'].to_s.downcase == val.to_s.downcase) || 
        (it['name'].to_s.downcase == val.to_s.downcase)
      }
    end
  end

  def get_available_preseed_scripts(refresh=false)
    if !@available_preseed_scripts || refresh
      # option_results = options_interface.options_for_source('preseedScripts',{})['data']
      preseed_scripts_dropdown = []
      scripts = @preseed_scripts_interface.list({max:1000})['preseedScripts']
      scripts.each do |it| 
        preseed_scripts_dropdown << {'name'=>it['fileName'],'value'=>it['id'],'id'=>it['id']}
      end
      # preseed_scripts_dropdown << {'name'=>'Custom','value'=> 'custom','value'=> 'custom'}
      @available_preseed_scripts = preseed_scripts_dropdown
    end
    #puts "available_preseed_scripts() rtn: #{@available_preseed_scripts.inspect}"
    return @available_preseed_scripts
  end

  def find_preseed_script(val)
    if val.nil? || val.to_s.empty?
      return nil
    else
      return get_available_preseed_scripts().find { |it| 
        (it['id'].to_s.downcase == val.to_s.downcase) || 
        (it['name'].to_s.downcase == val.to_s.downcase)
      }
    end
  end

  def prompt_edit_archive_bucket(archive_bucket, options={})
    # populate default prompt values with the existing archive bucket 
    default_values = archive_bucket.dup # lazy, but works as long as GET matches POST api structure
    # storage provider (cannot be edited anyhow..)
    if archive_bucket['storageProvider'].kind_of?(Hash)
      default_values['storageProvider'] = archive_bucket['storageProvider']['id']
    end
    # tenants
    if archive_bucket['accounts'].kind_of?(Array) && archive_bucket['accounts'].size > 0
      default_values['accounts'] = archive_bucket['accounts'].collect {|it| it['name'] }.join(", ")
    end
    # any other mismatches? preseedScript, bootScript?
    options[:is_edit] = true
    return prompt_new_archive_bucket(options, default_values)
  end

  def prompt_new_archive_bucket(options={}, default_values={})
    payload = {}

    # Name
    if options['name']
      payload['name'] = options['name']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this archive bucket.', 'defaultValue' => default_values['name']}], options, @api_client)
      payload['name'] = v_prompt['name']
    end

    # Description
    if options['description']
      payload['description'] = options['description']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'defaultValue' => default_values['description']}], options, @api_client)
      payload['description'] = v_prompt['description']
    end

    # Storage Provider
    unless options[:is_edit]
      if options['storageProvider']
        # payload['storageProvider'] = options['storageProvider']
        # prompt is skipped when options['fieldName'] is passed in, this will return an id from a name
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProvider', 'fieldLabel' => 'Storage Provider', 'type' => 'select', 'optionSource' => 'storageProviders', 'description' => 'Storage Provider', 'defaultValue' => options['storageProvider'], 'required' => true}], options, @api_client, {})
        payload['storageProvider'] = {id: v_prompt['storageProvider']}
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProvider', 'fieldLabel' => 'Storage Provider', 'type' => 'select', 'optionSource' => 'storageProviders', 'description' => 'Storage Provider', 'defaultValue' => default_values['storageProvider'], 'required' => true}], options, @api_client, {})
        payload['storageProvider'] = {id: v_prompt['storageProvider']}
      end
    end

    # Tenants
    # TODO: a nice select component for adding/removing from this array
    if options['accounts']
      payload['accounts'] = options['accounts'] #.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
    else
      tenants_default_value = default_values['accounts']
      if tenants_default_value.kind_of?(Array)
        tenants_default_value = tenants_default_value.collect {|it| it["id"] }.join(", ")
      end
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'accounts', 'fieldLabel' => 'Tenants', 'type' => 'text', 'description' => 'Tenant Accounts (comma separated ids)', 'defaultValue' => tenants_default_value}], options, @api_client)
      payload['accounts'] = v_prompt['accounts'].to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
    end

    # Visibility
    if options['visibility']
      payload['visibility'] = options['visibility']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'}, {'name' => 'Public', 'value' => 'public'}], 'defaultValue' => (default_values['visibility'] || 'private'), 'required' => true}], options, @api_client, {})
      payload['visibility'] = v_prompt['visibility']
    end

    # Public URL
    if options['isPublic']
      payload['isPublic'] = options['isPublic']
    else
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'isPublic', 'fieldLabel' => 'Public URL', 'type' => 'checkbox', 'description' => 'Enabling Public URL allows files to be downloaded without any authentication.', 'defaultValue' => (default_values['isPublic'].nil? ? false : default_values['isPublic']), 'required' => true}], options, @api_client, {})
      payload['isPublic'] = v_prompt['isPublic']
    end

    return payload
  end

  def print_archive_files_table(archive_files, options={})
    table_color = options[:color] || cyan
    rows = archive_files.collect do |archive_file|
      {
        id: archive_file['id'],
        name: options[:fullTree] ? archive_file['filePath'] : archive_file['name'],
        type: archive_file['isDirectory'] ? 'directory' : (archive_file['contentType']),
        size: format_bytes(archive_file['rawSize']),
        dateCreated: format_local_dt(archive_file['dateCreated']),
        lastUpdated: format_local_dt(archive_file['lastUpdated'])
      }
    end
    columns = [
      # :id,
      {:name => {:display_name => "File".upcase} },
      :type,
      :size,
      # {:dateCreated => {:display_name => "Date Created"} },
      {:lastUpdated => {:display_name => "Last Modified".upcase} }
    ]
    print table_color
    print as_pretty_table(rows, columns, options)
    print reset
  end

  def print_archive_logs_table(archive_logs, opts={})
    table_color = opts[:color] || cyan
    rows = archive_logs.collect do |archive_log|
      response_str = ""
      if archive_log['responseCode']
        if archive_log['responseCode'].to_i == 200
          response_str = "#{green}#{archive_log['responseCode']} #{archive_log['responseMessage']}".strip + table_color
        else
          response_str = "#{red}#{archive_log['responseCode']}#{reset} #{archive_log['responseMessage']}".strip + table_color
        end
      end
      if archive_log['fileSize'] && archive_log['fileSize'].to_i > 0
        response_str << " (#{format_bytes(archive_log['fileSize'])})"
      end
      request_str = "#{archive_log['requestUrl']}".strip
      # if archive_log['archiveFileLink']
      #   request_str << " [Link #{archive_log['archiveFileLink']['shortKey']}]"
      # end
      {
        id: archive_log['id'],
        eventType: archive_log['eventType'] ? archive_log['eventType'] : '',
        bucket: archive_log['archiveBucket'] ? archive_log['archiveBucket']['name'] : '',
        file: archive_log['archiveFile'] ? archive_log['archiveFile']['filePath'] : '',
        link: archive_log['archiveFileLink'] ? archive_log['archiveFileLink']['shortKey'] : '',
        description: archive_log['description'] ? archive_log['description'] : '',
        fileSize: format_bytes(archive_log['fileSize']),
        dateCreated: format_local_dt(archive_log['dateCreated']),
        user: archive_log['user'] ? archive_log['user']['username'] : '',
        webInterface: archive_log['webInterface'],
        #request: request_str,
        response: response_str
      }
    end
    columns = [
      {:dateCreated => {:display_name => "Date".upcase} },
      {:eventType => {:display_name => "Event".upcase} },
      :bucket,
      :file,
      :link,
      # :fileSize,
      :description,
      :user,
      {:webInterface => {:display_name => "Interface".upcase} },
      #:request,
      :response
    ]
    if opts[:exclude]
      columns = columns.reject {|c| 
          c.is_a?(Hash) ? opts[:exclude].include?(c.keys[0]) : opts[:exclude].include?(c)
      }
    end
    print table_color
    print as_pretty_table(rows, columns, opts)
    print reset
  end

  def print_archive_file_links_table(archive_file_links, opts={})
    table_color = opts[:color] || cyan
    rows = archive_file_links.collect do |archive_file_link|
      status_str = ""
      begin
        if archive_file_link['expirationDate'] && Time.now.utc > parse_time(archive_file_link['expirationDate'])
          status_str = red + "EXPIRED" + table_color
        else
          status_str = green + "ACTIVE" + table_color
        end
      rescue => ex
        Morpheus::Logging::DarkPrinter.puts "trouble parsing expiration date: #{ex.inspect}" if Morpheus::Logging.debug?
      end
      link_url = "/public-archives/link?s=" + archive_file_link['secretAccessKey'].to_s
      {
        url: link_url,
        created: format_local_dt(archive_file_link['dateCreated']),
        expires: archive_file_link['expirationDate'] ? format_local_dt(archive_file_link['expirationDate']) : 'Never',
        downloads: archive_file_link['downloadCount'],
        status: status_str
      }
    end
    columns = [
      {:url => {:display_name => "Link URL".upcase} },
      :created,
      :expires,
      :downloads,
      :status
    ]
    print table_color
    print as_pretty_table(rows, columns, opts)
    print reset
  end

  # parse_bucket_id_and_file_path() provides flexible argument formats for bucket and path
  # it looks for [bucket:/path] or [bucket] [path]
  # @param delim [String] Default is a comma and any surrounding white space.
  # @return [Array] 2 elements, bucket name (or id) and the file path.
  #         The default file path is "/".
  # Examples:
  #   parse_bucket_id_and_file_path("test") == ["test", "/"]
  #   parse_bucket_id_and_file_path("test:/global.cfg") == ["test", "/global.cfg"]
  #   parse_bucket_id_and_file_path("test:/node1/node.cfg") == ["test", "/node1/node.cfg"]
  #   parse_bucket_id_and_file_path("test/node1/node.cfg") == ["test", "/node1/node.cfg"]
  #   parse_bucket_id_and_file_path("test", "node1/node.cfg") == ["test", "/node1/node.cfg"]
  #
  def parse_bucket_id_and_file_path(*args)
    if args.size < 1 || args.size > 2
      return nil, nil
    end
    if !args[0]
      return nil, nil
    end
    full_path = args[0].to_s
    if args[1]
      if full_path.include?(":")
        full_path = "#{full_path}/#{args[1]}"
      else
        full_path = "#{full_path}:#{args[1]}"
      end
    end
    # ok fine, allow just bucketId/filePath, without a colon.
    if !full_path.include?(":") && full_path.include?("/")
      path_elements = full_path.split("/")
      full_path = path_elements[0] + ":" + path_elements[1..-1].join("/")
    end
    uri_elements = full_path.split(":")
    bucket_id = uri_elements[0]
    file_path = uri_elements[1..-1].join("/") # [1]
    file_path = "/#{file_path}".squeeze("/")
    return bucket_id, file_path
  end
end
