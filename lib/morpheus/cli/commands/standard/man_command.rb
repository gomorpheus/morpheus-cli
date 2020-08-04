require 'optparse'
require 'morpheus/logging'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::ManCommand
  include Morpheus::Cli::CliCommand
  set_command_name :man
  set_command_hidden

  # this should be read only anyway...
  @@default_editor = "less" # ENV['EDITOR']
  
  def handle(args)
    options = {}
    regenerate = false
    editor = @@default_editor
    open_as_link = false # true please
    goto_wiki = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus man"
      opts.on('-w','--wiki', "Open the morpheus-cli wiki instead of the local man page") do
        goto_wiki = true
      end
      opts.on('-e','--editor EDITOR', "Specify which program to open the manual with. Default is '#{editor}'.") do |val|
        editor = val
        open_as_link = false
      end
      opts.on('-g','--generate', "Regenerate the manual file") do
        regenerate = true
      end
      opts.on('-q','--quiet', "Do not open manual, for use with the -g option.") do
        options[:quiet] = true
      end
      #build_common_options(opts, options, [:quiet])
      # disable ANSI coloring
      opts.on('-C','--nocolor', "Disable ANSI coloring") do
        Term::ANSIColor::coloring = false
      end

      opts.on('-V','--debug', "Print extra output for debugging. ") do
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      end
      opts.on('-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
      opts.footer = <<-EOT
Open the morpheus manual located at #{Morpheus::Cli::ManCommand.man_file_path}
The -g switch be used to regenerate the file.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    if goto_wiki
      link = "https://github.com/gomorpheus/morpheus-cli/wiki/CLI-Manual"
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        system "xdg-open #{link}"
      end
      return 0, nil
    end

    fn = Morpheus::Cli::ManCommand.man_file_path
    if regenerate || !File.exists?(fn)
      #Morpheus::Logging::DarkPrinter.puts "generating manual #{fn} ..." if Morpheus::Logging.debug? && !options[:quiet]
      Morpheus::Cli::ManCommand.generate_manual(options)
    end
    
    if options[:quiet]
      return 0, nil
    end
    
    Morpheus::Logging::DarkPrinter.puts "opening manual file #{fn}" if Morpheus::Logging.debug? && !options[:quiet]
    
    
    if open_as_link # not used atm
      link = "file://#{fn}"
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        system "xdg-open #{link}"
      end
      return 0, nil
    else
      if editor
        if !system_command_available?(editor)
          raise_command_error "The editor program '#{editor}' is not available on your system."
          # puts_error "#{red}The editor program '#{editor}' is not available on your system.#{reset}"
          # return 1
        end        
        system("#{editor} #{fn}")
      else
        raise_command_error "Tell me how to open the manual file #{fn}. Try -e emacs or run export EDITOR=emacs"
        return 1
      end
    end

    return 0, nil
  end

  # determine if system command is available
  # uses *nix's `which` command.
  # Prevents using dangerous commands rm,mv,passwd
  # todo: support for Windows and PowerShell
  def system_command_available?(cmd)
    has_it = false
    begin
      cmd = cmd.strip.gsub("'",'')
      system("which '#{cmd}' > /dev/null 2>&1")
      has_it = $?.success?
    rescue => e
      raise e
    end
    return has_it
  end

  def self.man_file_path
    File.join(Morpheus::Cli.home_directory, "CLI-Manual-#{Morpheus::Cli::VERSION}.md")
  end

  # def self.save_manual(fn, content)
  #   # fn = man_file_path()
  #   if !Dir.exists?(File.dirname(fn))
  #     FileUtils.mkdir_p(File.dirname(fn))
  #   end
  #   Morpheus::Logging::DarkPrinter.puts "saving manual to #{fn}" if Morpheus::Logging.debug?
  #   File.open(fn, 'w') {|f| f.write content.to_s } #Store
  #   FileUtils.chmod(0600, fn)
  # end

  def self.generate_manual(options={})
    # todo: use pandoc or something else to convert the CLI-Manual.md to a man page
    # and install it, so the os command `man morpheus` will work too.
    fn = man_file_path()
    if !Dir.exists?(File.dirname(fn))
      FileUtils.mkdir_p(File.dirname(fn))
    end
    Morpheus::Logging::DarkPrinter.puts "generating manual #{fn}" if Morpheus::Logging.debug? && !options[:quiet]

    File.open(fn, 'w') {|f| f.write("") } # clear file
    FileUtils.chmod(0600, fn)

    manpage = File.new(fn, 'w')
    # previous_stdout = $stdout
    # previous_stdout = STDOUT
    # $stdout = manpage
    begin

      manpage.print <<-ENDTEXT
morpheus v#{Morpheus::Cli::VERSION}

## NAME

    morpheus - the command line interface for interacting with the Morpheus appliance

## SYNOPSIS

    morpheus [command] [<args>] [options]

## DESCRIPTION

    Morpheus CLI

    This is a command line interface for managing a Morpheus Appliance.
    All communication with the remote appliance is done via the Morpheus API.

    To get started, see the command `remote add` command.

    To learn more, visit https://github.com/gomorpheus/morpheus-cli/wiki/Getting-Started

    To learn more about the Morpheus Appliance, visit https://www.morpheusdata.com/features

    To learn more about the Morpheus API, visit https://apidocs.morpheusdata.com

## GLOBAL OPTIONS

    Morpheus supports a few global options.

    -v, --version                    Print the version.
        --noprofile                  Do not read and execute the personal initialization script .morpheus_profile
    -C, --nocolor                    Disable ANSI coloring
    -V, --debug                      Print extra output for debugging. 
    -h, --help                       Print this help

## COMMON OPTIONS

    There are some common options that many commands support. They work the same way for each command.

    -O, --option OPTION              Option value in the format -O var="value" (deprecated soon in favor of first class options)
    -N, --no-prompt                  Skip prompts. Use default values for all optional fields.
    -j, --json                       JSON Output
    -d, --dry-run                    Dry Run, print the API request instead of executing it
    -r, --remote REMOTE              Remote Appliance Name to use for this command. The active appliance is used by default.
    -I, --insecure                   Allow for insecure HTTPS communication i.e. bad SSL certificate       
    -y, --yes                        Auto confirm, skip any 'Are you sure?' confirmations.
    -r, --quiet                      No Output, when successful.

## MORPHEUS COMMANDS

    We divide morpheus into commands.  
    Every morpheus command may have 0-N sub-commands that it supports. 
    Commands generally map to the functionality provided in the Morpheus UI.
       
    You can get help for any morpheus command by using the -h option.

    The available commands and their options are also documented below.
ENDTEXT
      
      terminal = Morpheus::Terminal.new($stdin, manpage)
      Morpheus::Logging::DarkPrinter.puts "appending command help `morpheus --help`" if Morpheus::Logging.debug? && !options[:quiet]

      manpage.print "\n"
      manpage.print "## morpheus\n"
      manpage.print "\n"
      manpage.print "```\n"
      exit_code, err = terminal.execute("--help")
      manpage.print "```\n"
      manpage.print "\n"
      # output help for every command (that is not hidden)
      Morpheus::Cli::CliRegistry.all.keys.sort.each do |cmd|
        cmd_klass = Morpheus::Cli::CliRegistry.instance.get(cmd)
        cmd_instance = cmd_klass.new
        Morpheus::Logging::DarkPrinter.puts "appending command help `morpheus #{cmd} --help`" if Morpheus::Logging.debug? && !options[:quiet]
        #help_cmd = "morpheus #{cmd} --help"
        #help_output = `#{help_cmd}`
        manpage.print "\n"
        manpage.print "### morpheus #{cmd}\n"
        manpage.print "\n"
        manpage.print "```\n"
        begin
          cmd_instance.handle(["--help"])
        rescue SystemExit => err
          raise err unless err.success?
        end
        manpage.print "```\n"
        # subcommands = cmd_klass.subcommands
        subcommands = cmd_klass.visible_subcommands
        if subcommands && subcommands.size > 0
          subcommands.sort.each do |subcommand, subcommand_method|
            Morpheus::Logging::DarkPrinter.puts "appending command help `morpheus #{cmd} #{subcommand} --help`" if Morpheus::Logging.debug? && !options[:quiet]
            manpage.print "\n"
            manpage.print "#### morpheus #{cmd} #{subcommand}\n"
            manpage.print "\n"
            manpage.print "```\n"
            begin
              cmd_instance.handle([subcommand, "--help"])
            rescue SystemExit => err
              raise err unless err.success?
            end
            manpage.print "```\n"
            # manpage.print "\n"
          end
        end
        manpage.print "\n"
      end

      manpage.print <<-ENDTEXT

## ENVIRONMENT VARIABLES

Morpheus has only one environment variable that it uses.

### MORPHEUS_CLI_HOME

The **MORPHEUS_CLI_HOME** variable is where morpheus CLI stores its configuration files.
This can be set to allow a single system user to maintain many different configurations
If the directory does not exist, morpheus will attempt to create it.

The default home directory is **$HOME/.morpheus**

To see how this works, run the following:

```shell
MORPHEUS_CLI_HOME=~/.morpheus_test morpheus shell
```

Now, in your new morpheus shell, you can see that it is a fresh environment.
There are no remote appliances configured.

```shell
morpheus> remote list

Morpheus Appliances
==================

You have no appliances configured. See the `remote add` command.

```

You can use this to create isolated environments (sandboxes), within which to execute your morpheus commands.

```shell
export MORPHEUS_CLI_HOME=~/morpheus_test
morpheus remote add demo https://demo.mymorpheus.com --insecure
morpheus instances list
```

Morpheus saves the remote appliance information, including api access tokens, 
to the $MORPHEUS_HOME_DIRECTORY. These files are saved with file permissions **6000**.
So, only one system user should be allowed to execute morpheus with that home directory.
See [Configuration](#Configuration) for more information on the files morpheus reads and writes.

## CONFIGURATION

Morpheus reads and writes several configuration files within the $MORPHEUS_CLI_HOME directory.

**Note:** These files are maintained by the program. It is not recommended for you to manipulate them.

### appliances file

The `appliances` YAML file contains a list of known appliances, keyed by name.

Example:
```yaml
:qa:
  :host: https://qa.mycoolsite.com
  :active: true
:production:
  :host: https://morpheus.mycoolsite.com
  :active: false
```

### credentials file

The `.morpheus/credentials` YAML file contains access tokens for each known appliance.

### groups file

The `.morpheus/groups` YAML file contains the active group information for each known appliance.


## Startup scripts

When Morpheus starts, it executes the commands in a couple of dot files.

These scripts are written in morpheus commands, not bash, so they can only execute morpheus commands and aliases. 

### .morpheus_profile file

It looks for `$MORPHEUS_CLI_HOME/.morpheus_profile`, and reads and executes it (if it exists). 

This may be inhibited by using the `--noprofile` option.

### .morpheusrc file

When started as an interactive shell with the `morpheus shell` command,
Morpheus reads and executes `$MORPHEUS_CLI_HOME/.morpheusrc` (if it exists). This may be inhibited by using the `--norc` option. 

An example startup script might look like this:

```
# .morpheusrc

# aliases
alias our-instances='instances list -c "Our Cloud"'

# switch to our appliance that we created with `remote add morphapp1`
remote use morphapp1

# greeting
echo "Welcome back human,  have fun!"

# print current user information
whoami

# print the list of instances in our cloud
our-instances

```

ENDTEXT

    ensure
      manpage.close if manpage
      # $stdout = previous_stdout if previous_stdout
      # this is needed to re-establish instance with STDOUT, STDIN
      terminal = Morpheus::Terminal.new()
    end

    return true
  end

end
