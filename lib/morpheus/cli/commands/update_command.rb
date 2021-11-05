require 'morpheus/cli/cli_command'

# This is for use in dotfile scripts and the shell..
class Morpheus::Cli::UpdateCommand
  include Morpheus::Cli::CliCommand
  set_command_name :update

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name}"
      opts.on( '-f', '--force', "Force Update, executes update even if latest version is already installed." ) do
        options[:force] = true
      end
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "This will update the morpheus command line interface to the latest version.\nThis is done by executing the system command: `gem update #{morpheus_gem_name}`"
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)

    current_version = Morpheus::Cli::VERSION
    latest_version = get_latest_version()
    latest_version = latest_version
    
    if current_version == latest_version && !options[:force]
      unless options[:quiet]
        print cyan, "The latest version is already installed. (#{latest_version})", "\n", reset
      end
      return 0, nil
    end

    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to update the #{morpheus_gem_name} gem from version #{current_version} to version #{latest_version}?")
      return 9, "aborted command"
    end

    gem_update_command = "gem update #{morpheus_gem_name}"

    if options[:dry_run]
      unless options[:quiet]
        print "\n"
        print "#{cyan}#{bold}#{dark}COMMAND#{reset}\n"
        puts gem_update_command
        print "\n", reset
      end
      return 0, nil
    end
    
    # ok, update it
    if options[:quiet]
      system(gem_update_command)
    else
      `#{gem_update_command}`
    end

    if $?.success?
      return 0, nil
    else
      return $?.exitstatus, "update failed"
    end

  end

  protected

  def morpheus_gem_name
    'morpheus-cli'
  end

  def get_latest_version
    result = HTTP.get("https://rubygems.org/api/v1/gems/#{morpheus_gem_name}.json")
    json_response = JSON.parse(result.body)
    json_response["version"]
  end

end
