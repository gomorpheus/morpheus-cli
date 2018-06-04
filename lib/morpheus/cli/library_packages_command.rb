require 'io/console'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/library_helper'

class Morpheus::Cli::LibraryPackagesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-packages'
  register_subcommands :download
  # register_subcommands :upload

  # hide until this is released
  set_command_hidden

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_packages_interface = @api_client.library_packages
    @library_instance_types_interface = @api_client.library_instance_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  # generate a new .mlp file
  def download(args)
    full_command_string = "#{command_name} download #{args.join(' ')}".strip
    options = {}
    params = {}
    instance_type_codes = nil
    outfile = nil
    do_overwrite = false
    do_mkdir = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[filename] --instance-types x,y,z")
      opts.on('--instance-types LIST', String, "List of instance type codes to export") do |val|
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
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "Download one or many instance types as a morpheus library package (.mlp) file.\n" + 
                    "[filename] is required. This is the local path for the downloaded .mlp file." +
                    "--instance-types is required. This is a list of instance type codes."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} download expects 1 argument and received #{args.count}: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # construct payload
      if !params['all']
        if !instance_type_codes
          puts_error "#{Morpheus::Terminal.angry_prompt}option --instance-types is required.\n#{optparse}"
          return 1
        end
        params['instanceType'] = instance_type_codes
      end

      # determine outfile
      outfile = args[0]
      # if !outfile
      #   # use a default location
      #   do_mkdir = true
      #   if instance_type_codes.size == 1
      #     outfile = File.join(Morpheus::Cli.home_directory, "tmp", "packages",  + "#{instance_type_codes[0]}.mlp")
      #   else
      #     outfile = File.join(Morpheus::Cli.home_directory, "tmp", "packages",  "download.mlp")
      #   end
      # end
      outfile = File.expand_path(outfile)
      if Dir.exists?(outfile)
        puts_error "#{Morpheus::Terminal.angry_prompt}[filename] is invalid. It is the name of an existing directory: #{outfile}"
        return 1
      end
      # always a .mlp
      # if outfile[-4..-1] != ".mlp"
      #   outfile << ".mlp"
      # end
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

      if options[:dry_run]
        print_dry_run @library_packages_interface.dry.download(params, outfile), full_command_string
        return 1
      end
      if !options[:quiet]
        print cyan + "Downloading morpheus package file #{outfile} ... "
      end

      http_response, bad_body = @library_packages_interface.download(params, outfile)

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


  def upload
    raise "not yet implemented"
  end


  private

  

end
