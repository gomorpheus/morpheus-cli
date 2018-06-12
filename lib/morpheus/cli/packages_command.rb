require 'fileutils'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryPackagesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'packages'
  # register_subcommands :list, :get, :install, :update, :remove, :export
  register_subcommands :list, :search, :export

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

      if options[:dry_run]
        print_dry_run @packages_interface.dry.list(params)
        return
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
          columns = [:code, :name, {:description => {:max_width => 50}}]
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
      params.merge!(parse_list_options(options))

      if options[:dry_run]
        print_dry_run @packages_interface.dry.search(params)
        return
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
              version: package['version'],
              description: package['description']
            }
          }
          columns = [:code, :name, {:description => {:max_width => 50}}]
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
    raise "not yet implemented"
  end

  def install(args)
    raise "not yet implemented"
  end

  def update(args)
    raise "not yet implemented"
  end

  def remove(args)
    raise "not yet implemented"
  end

  # generate a new .morpkg file
  def export(args)
    full_command_string = "#{command_name} export #{args.join(' ')}".strip
    options = {}
    params = {}
    instance_type_codes = nil
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    unzip_and_open = false
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
      opts.on( '--open [PROG]', String, "Unzip the package and open the expanded directory with the specified program." ) do |val|
        unzip_and_open = true
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
      opts.footer = "Export one or many instance types as a morpheus library package (.morpkg) file.\n" + 
                    "[instance-type] is required. This is the instance type code." +
                    "--instance-types can bv. This is a list of instance type codes."
    end
    optparse.parse!(args)

    if args.count != 1 && !instance_type_codes && !params['all']
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} export expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
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
      if Dir.exists?(outfile)
        puts_error "#{Morpheus::Terminal.angry_prompt}--file is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      # always a .morpkg
      if outfile[-7..-1] != ".morpkg"
        outfile << ".morpkg"
      end
      destination_dir = File.dirname(outfile)
      if !Dir.exists?(destination_dir)
        if do_mkdir
          print cyan,"Creating local directory #{destination_dir}",reset,"\n"
          FileUtils.mkdir_p(destination_dir)
        else
          puts_error "#{Morpheus::Terminal.angry_prompt}[filename] is invalid. Directory not found: #{destination_dir}  Use -p to create the missing directory."
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
          puts_error "[filename] is invalid. File already exists: #{outfile}", "Use -f to overwrite the existing file."
          # puts_error optparse
          return 1
        end
      end

      # merge -O options into normally parsed options
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      if options[:dry_run]
        print_dry_run @packages_interface.dry.export(params, outfile), full_command_string
        return 1
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

        if unzip_and_open
          package_dir = File.join(File.dirname(outfile), File.basename(outfile).sub(/\.morpkg\Z/, ''))
          if File.exists?(package_dir)
            print cyan,"Deleting existing directory #{package_dir}",reset,"\n"
            FileUtils.rm_rf(package_dir)
          end
          print cyan,"Unzipping to #{package_dir}",reset,"\n"
          system("unzip '#{outfile}' -d '#{package_dir}' > /dev/null 2>&1")
          system("#{open_prog} '#{package_dir}'")
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

  

end
