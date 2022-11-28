require 'morpheus/cli/cli_command'
require 'morpheus/morpkg'

class Morpheus::Cli::PackagesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'packages'
  register_subcommands :list, :search, :get, :install, :update, :remove, :export, :build
  register_subcommands :'install-file' => :install_file

  # hide until this is released
  set_command_hidden

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @packages_interface = @api_client.packages
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List installed packages."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @packages_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @packages_interface.dry.list(params)
        return 0
      end
      json_response = @packages_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "packages")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "packages")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["packages"], options)
      else
        installed_packages = json_response["packages"]
        title = "Installed Packages"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if installed_packages.empty?
          print cyan,"No installed packages found",reset,"\n"
        else
          rows = installed_packages.collect {|package|
            {
              code: package['code'],
              name: package['name'],
              version: package['version'],
              description: package['description'],
            }
          }
          columns = [:code, :name, {:description => {:max_width => 50}}, :version]
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def search(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Search the marketplace for available packages."
    end
    optparse.parse!(args)
    connect(options)
    begin
      if args[0]
        options[:phrase] = args[0]
        # params['phrase'] = args[0]
      end
      params.merge!(parse_list_options(options))
      @packages_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @packages_interface.dry.search(params)
        return 0
      end
      json_response = @packages_interface.search(params)
      if options[:json]
        puts as_json(json_response, options, "packages")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "packages")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["packages"], options)
      else
        available_packages = json_response["packages"]
        title = "Available Packages"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if available_packages.empty?
          print cyan,"No packages found",reset,"\n"
        else
          rows = available_packages.collect {|package|
            {
              code: package['code'],
              name: package['name'],
              description: package['description'],
              versions: (package['versions'] || []).collect {|v| v['version'] }.join(', ')
            }
          }
          columns = [:code, :name, {:description => {:max_width => 50}}, {:versions => {:max_width => 30}}]
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[code]")
      opts.on( nil, '--versions', "Display Available Versions" ) do
        options[:show_versions] = true
      end
      opts.on( nil, '--objects', "Display Installed Package Objects" ) do
        options[:show_objects] = true
      end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a package.\n" + 
                    "[code] is required. This is the package code."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} get expects 1 argument and received #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    begin
      params.merge!(parse_list_options(options))
      params['code'] = args[0]
      @packages_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @packages_interface.dry.info(params)
        return 0
      end
      json_response = @packages_interface.info(params)
      if options[:json]
        puts as_json(json_response, options, "package")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "package")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["package"], options)
      else
        installed_package = json_response["package"]
        available_package = json_response["availablePackage"]

        if installed_package.nil? && available_package.nil?
          print yellow,"No package found for code '#{params['code']}'",reset,"\n"
          return 1
        end

        print_h1 "Package Info"
      
        # merge installed and available package info
        package_record = installed_package || available_package
        #package_record['versions'] = available_package['versions'] if available_package
        print cyan
        description_cols = {
          # "Organization" => 'organization',
          "Code" => 'code',
          "Name" => 'name',
          "Description" => 'description',
          # "Type" => lambda {|it| (it['packageType'] || it['type']).to_s },
          "Latest Version" => lambda {|it| 
            if available_package && available_package['versions']
              latest_version = available_package['versions'].find {|v| v['latestVersion'] }
              if latest_version.nil?
                sorted_versions = available_package['versions'].sort {|x,y|  x['dateCreated'] <=> y['dateCreated'] }
                latest_version = sorted_versions.first()
              end
              latest_version ? latest_version['version'] : ""
            else
              ""
            end
          },
          "Installed Version" => lambda {|it| 
            installed_package ? installed_package['version'] : ""
          },
          "Status" => lambda {|it| 
            installed_package ? format_package_status(installed_package['status']) : format_package_status(nil)
           },
        }
        if installed_package.nil?
          description_cols.delete("Installed Version")
        end

        print_description_list(description_cols, package_record)
        # print reset, "\n"
        if options[:show_versions]
          print_h2 "Available Versions"
          if available_package.nil?
            print yellow,"No marketplace package found for code '#{params['code']}'",reset,"\n"
          else
            if available_package['versions'].nil? || available_package['versions'].empty?
              print yellow,"No available versions found",reset,"\n"
            else
              # api is sorting these with latestVersion first, right?
              sorted_versions = available_package['versions'] || []
              #sorted_versions = available_package['versions'].sort {|x,y|  x['dateCreated'] <=> y['dateCreated'] }
              rows = sorted_versions.collect {|package_version|
                {
                  "PACKAGE VERSION": package_version['version'],
                  "MORPHEUS VERSION": package_version['minApplianceVersion'],
                  "PUBLISH DATE": format_local_dt(package_version['created'] || package_version['dateCreated'])
                }
              }
              columns = ["PACKAGE VERSION", "MORPHEUS VERSION", "PUBLISH DATE"]
              print cyan
              print as_pretty_table(rows, columns)
              # print reset, "\n"
            end
          end
        end
        if options[:show_objects]
          print_h2 "Package Objects"
          if installed_package.nil?
            print cyan,"No objects to show",reset,"\n"
          else
            if installed_package['objects'].nil? || installed_package['objects'].empty?
              print yellow,"No objects to show",reset,"\n"
            else
              rows = installed_package['objects'].collect {|it|
                {
                  type: it['refType'],
                  id: it['refId'],
                  name: it['displayName']
                }
              }
              columns = [:type, :id, :name]
              print cyan
              print as_pretty_table(rows, columns)
              # print reset, "\n"
            end
          end
        end
        
        print reset, "\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def install(args)
    full_command_string = "#{command_name} install #{args.join(' ')}".strip
    options = {}
    params = {}
    open_prog = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[code]")
      opts.on('-v','--version VERSION', "Package Version number") do |val|
        params['version'] = val
      end
      # opts.on('--package-version VALUE', String, "Version number for package.") do |val|
      #   params['version'] = val
      # end
      opts.on('--organization NAME', String, "Package Organization.  Default is morpheus.") do |val|
        params['organization'] = val
      end
      opts.on( '-f', '--force', "Force Install." ) do
        params['force'] = true
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote, :quiet])
      opts.footer = "Install a morpheus package from the marketplace.\n" + 
                    "[code] is required. This is the package code."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} install expects 1 argument and received #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      params['code'] = args[0]
      @packages_interface.setopts(options)
      if options[:dry_run]
        #print cyan,bold, "  - Uploading #{local_file_path} to #{bucket_id}:#{destination} DRY RUN", reset, "\n"
        # print_h1 "DRY RUN"
        print_dry_run @packages_interface.dry.install(params)
        print "\n"
        return 0
      end
      
      json_response = @packages_interface.install(params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        package_str = params['code'] || ""
        installed_package = json_response['package']
        if installed_package && installed_package['code']
          package_str = installed_package['code']
        end
        if installed_package && installed_package['version']
          package_str = "#{package_str} #{installed_package['version']}"
        end
        print_green_success "Installed package #{package_str}"
      end
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def install_file(args)
    full_command_string = "#{command_name} install-file #{args.join(' ')}".strip
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[morpkg-file]")
      # opts.on('--url URL', String, "Use a remote URL as the source .morpkg instead of uploading a file.") do |val|
      #   params['url'] = val
      # end
      opts.on( '-f', '--force', "Force Install." ) do
        params['force'] = true
      end
      build_common_options(opts, options, [:options, :dry_run, :quiet])
      opts.footer = "Install a morpheus package with a .morpkg file directly.\n" + 
                    "[morpkg-file] is required. This is the local filepath of a .morpkg to be uploaded and installed."
    end
    optparse.parse!(args)

    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "expects 1 argument and received #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end

    # validate local file path
    local_file_path = File.expand_path(args[0].squeeze('/'))
    if local_file_path == "" || local_file_path == "/" || local_file_path == "."
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "bad argument: [morpkg-file]\nFile '#{local_file_path}' is invalid.\n#{optparse}"
      return 1
    end
    if !File.exist?(local_file_path)
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "bad argument: [morpkg-file]\nFile '#{local_file_path}' was not found.\n"
      return 1
    end
    if !File.file?(local_file_path)
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "bad argument: [morpkg-file]\nFile '#{local_file_path}' is not a file.\n"
      return 1
    end

    connect(options)
    begin
      @packages_interface.setopts(options)
      if options[:dry_run]
        #print cyan,bold, "  - Uploading #{local_file_path} to #{bucket_id}:#{destination} DRY RUN", reset, "\n"
        # print_h1 "DRY RUN"
        print_dry_run @packages_interface.dry.install_file(local_file_path, params)
        print "\n"
        return 0
      end
      
      json_response = @packages_interface.install_file(local_file_path, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        package_str = params['code'] || ""
        installed_package = json_response['package']
        if installed_package && installed_package['code']
          package_str = installed_package['code']
        end
        if installed_package && installed_package['version']
          package_str = "#{package_str} #{installed_package['version']}"
        end
        print_green_success "Installed package #{package_str}"
      end
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    raise "not yet implemented"
  end

  def remove(args)
    raise "not yet implemented"
  end

  # download a new .morpkg for remote instanceType(s)
  def export(args)
    full_command_string = "#{command_name} export #{args.join(' ')}".strip
    options = {}
    params = {}
    instance_type_codes = nil
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    do_unzip = false
    do_open = false
    open_prog = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance-type]")
      opts.on('--file FILE', String, "Destination filepath for the downloaded .morpkg file.") do |val|
        outfile = val
      end
      opts.on('--package-version VALUE', String, "Version number for package.") do |val|
        params['version'] = val
      end
      opts.on('--organization NAME', String, "Organization for package.") do |val|
        params['organization'] = val
      end
      opts.on('--code VALUE', String, "Code for package. Default comes from instance type.") do |val|
        params['code'] = val
      end
      opts.on('--name VALUE', String, "Name for package. Default comes from the instance type name") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description of package.") do |val|
        params['description'] = val
      end
      opts.on('--instance-types LIST', String, "Can be used to export multiple instance types as a single package.") do |val|
        instance_type_codes = []
        val.split(',').collect do |it|
          if !it.strip.empty?
            instance_type_codes << it.strip
          end
        end
      end
      opts.on('--all', String, "Export entire library instead of specific instance type(s).") do
        params['all'] = true
      end
      opts.on('--all-system', String, "Export all system instance types instead of specific instance type(s).") do
        params['all'] = true
        params['systemOnly'] = true
      end
      opts.on('--all-custom', String, "Export all custom instance types instead of specific instance type(s).") do
        params['all'] = true
        params['customOnly'] = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [filename] if they do not exist." ) do
        do_mkdir = true
      end
      opts.on( '-f', '--force', "Overwrite existing [filename] if it exists. Also creates missing directories." ) do
        do_overwrite = true
        do_mkdir = true
      end
      opts.on( '--unzip', "Unzip the package to a directory with the same name." ) do
        do_unzip = true
      end
      opts.on( '--open [PROG]', String, "Unzip the package and open the expanded directory with the specified program." ) do |val|
        do_unzip = true
        do_open = true
        if !val.to_s.empty?
          open_prog = val.to_s
        else
          if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
            open_prog = "start"
          elsif RbConfig::CONFIG['host_os'] =~ /darwin/
            open_prog = "open"
          elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
            open_prog = "xdg-open"
          end
        end
      end
      build_common_options(opts, options, [:options, :dry_run, :quiet])
      opts.footer = "Export one or many instance types as a morpheus package (.morpkg) file.\n" + 
                    "[instance-type] is required. This is the instance type code." +
                    "--instance-types can be export multiple instance types at once. This is a list of instance type codes."
    end
    optparse.parse!(args)

    if args.count != 1 && !instance_type_codes && !params['all']
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} export expects 1 argument and received #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # construct payload
      if !params['all']
        if args[0] && !instance_type_codes
          instance_type_codes = [args[0]]
        end
        params['instanceType'] = instance_type_codes
      end
      # determine outfile
      if !outfile
        # use a default location
        do_mkdir = true
        if instance_type_codes && instance_type_codes.size == 1
          outfile = File.join(Morpheus::Cli.home_directory, "tmp", "morpheus-packages", "#{instance_type_codes[0]}.morpkg")
        else
          outfile = File.join(Morpheus::Cli.home_directory, "tmp", "morpheus-packages", "download.morpkg")
        end
      end
      outfile = File.expand_path(outfile)
      if Dir.exist?(outfile)
        puts_error "#{Morpheus::Terminal.angry_prompt}--file is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      # always a .morpkg
      if outfile[-7..-1] != ".morpkg"
        outfile << ".morpkg"
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exist?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          puts_error "#{Morpheus::Terminal.angry_prompt}[filename] is invalid. Directory not found: #{destination_dir}  Use -p to create the missing directory."
          return 1
        end
      end
      if File.exist?(outfile)
        if do_overwrite
          # uhh need to be careful wih the passed filepath here..
          # don't delete, just overwrite.
          # File.delete(outfile)
        else
          print_error Morpheus::Terminal.angry_prompt
          puts_error "[filename] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
          # puts_error optparse
          return 1
        end
      end

      # merge -O options into normally parsed options
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      @packages_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @packages_interface.dry.export(params, outfile), full_command_string
        return 0
      end
      if !options[:quiet]
        print cyan + "Downloading morpheus package file #{outfile} ... "
      end

      http_response, bad_body = @packages_interface.export(params, outfile)

      # FileUtils.chmod(0600, outfile)
      success = http_response.code.to_i == 200
      if success
        if !options[:quiet]
          print green + "SUCCESS" + reset + "\n"
        end

        if do_unzip
          package_dir = File.join(File.dirname(outfile), File.basename(outfile).sub(/\.morpkg\Z/, ''))
          if File.exist?(package_dir)
            print cyan,"Deleting existing directory #{package_dir}",reset,"\n"
            FileUtils.rm_rf(package_dir)
          end
          print cyan,"Unzipping to #{package_dir}",reset,"\n"
          system("unzip '#{outfile}' -d '#{package_dir}' > /dev/null 2>&1")
          if do_open
            system("#{open_prog} '#{package_dir}'")
          end
        end

        return 0
      else
        if !options[:quiet]
          print red + "ERROR" + reset + " HTTP #{http_response.code}" + "\n"
          if bad_body
            puts red + bad_body
          end
          #response_body = (http_response.body.kind_of?(Net::ReadAdapter) ? "" : http_response.body)
        end
        # F it, just remove a bad result
        if File.exist?(outfile) && File.file?(outfile)
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

  # generate a new .morpkg for a local source directory
  def build(args)
    full_command_string = "#{command_name} build #{args.join(' ')}".strip
    options = {}
    source_directory = nil
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[source] [target]")
      opts.on('--source FILE', String, "Source directory of the package being built.") do |val|
        source_directory = val
      end
      opts.on('--target FILE', String, "Destination filename for the .morpkg output file. Default is [code]-[version].morpkg") do |val|
        outfile = val
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [target] if they do not exist." ) do
        do_mkdir = true
      end
      opts.on( '-f', '--force', "Overwrite existing [target] if it exists. Also creates missing directories." ) do
        do_overwrite = true
        do_mkdir = true
      end
     
      build_common_options(opts, options, [:options, :dry_run, :quiet])
      opts.footer = "Generate a new morpheus package file. \n" + 
                    "[source] is required. This is the source directory of the package.\n" +
                    "[target] is the output filename. The default is [code]-[version].morpkg"
    end
    optparse.parse!(args)

    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1-2 and got #{args.count}\n#{optparse}"
      return 1
    end
    if args[0]
      source_directory = args[0]
    end
    if args[1]
      outfile = args[1]
    end
    if !source_directory
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "missing required argument [source]\n#{optparse}"
      return 1
    end
    
    # connect(options)
    begin  
      # validate source
      source_directory = File.expand_path(source_directory)
      if !File.exist?(source_directory)
        puts_error "#{Morpheus::Terminal.angry_prompt}[source] is invalid. Directory not found: #{source_directory}"
        return 1
      end
      if !File.directory?(source_directory)
        puts_error "#{Morpheus::Terminal.angry_prompt}[source] is invalid. Not a directory: #{source_directory}"
        return 1
      end
      # parse package source

      package_org = nil
      package_code = nil
      package_version = nil
      package_type = nil


      # validate package
      if !package_code.nil? || package_code.empty?
        puts_error "#{Morpheus::Terminal.angry_prompt}package data is invalid. Missing package code."
        return 1
      end
      if package_version.nil? || package_version.empty?
        puts_error "#{Morpheus::Terminal.angry_prompt}package data is invalid. Missing package version."
        return 1
      end
      # determine outfile
      if !outfile
        outfile = File.join(File.dirname(source_directory), "#{package_code}-#{package_version}.morpkg")
      else
        outfile = File.expand_path(outfile)
      end
      if Dir.exist?(outfile)
        puts_error "#{Morpheus::Terminal.angry_prompt}[target] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      # always a .morpkg
      if outfile[-7..-1] != ".morpkg"
        outfile << ".morpkg"
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exist?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          puts_error "#{Morpheus::Terminal.angry_prompt}[target] is invalid. Directory not found: #{destination_dir}  Use -p to create the missing directory."
          return 1
        end
      end
      if File.exist?(outfile)
        if do_overwrite
          # uhh need to be careful wih the passed filepath here..
          # don't delete, just overwrite.
          # File.delete(outfile)
        else
          puts_error "#{Morpheus::Terminal.angry_prompt}[target] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
          return 1
        end
      end

      if options[:dry_run]
        print cyan + "Building morpheus package at #{source_directory} ..."
        print cyan + "DRY RUN" + reset + "\n"
        return 0
      end
      if !options[:quiet]
        print cyan + "Building morpheus package at #{source_directory} ... "
      end

      # build it
      #http_response, bad_body = @packages_interface.export(params, outfile)

      # FileUtils.chmod(0600, outfile)
      success = true
      error_msg = nil
      build_outfile = nil
      begin
        build_outfile = Morpheus::Morpkg.build_package(source_directory, outfile, options[:force])
        success = true
      rescue => ex
        error_msg = ex.message
      end
      if success
        if !options[:quiet]
          print green + "SUCCESS" + reset + "\n"
          print green + "Generated #{build_outfile}" + reset + "\n"
        end
        return 0
      else
        if !options[:quiet]
          print red + "ERROR" + reset + "\n"
          if error_msg
            print_error red + error_msg + reset + "\n"
          end
        end
        # F it, just remove a bad result
        # if File.exist?(outfile) && File.file?(outfile)
        #   Morpheus::Logging::DarkPrinter.puts "Deleting bad build file: #{outfile}" if Morpheus::Logging.debug?
        #   File.delete(outfile)
        # end
        if options[:debug]
          # puts_error error_msg
        end
        return 1
      end
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

  def format_package_status(status_string, return_color=cyan)
    out = ""
    if status_string == 'installed'
      out <<  "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'uninstalled' || status_string == 'removed'
      out <<  "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'installing'
      out <<  "#{cyan}#{status_string.upcase}#{return_color}"
    elsif status_string.nil?
      out <<  "#{cyan}NOT INSTALLED#{return_color}"
    elsif !status_string.nil?
      out <<  "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out <<  ""
    end
    out
  end  

end
