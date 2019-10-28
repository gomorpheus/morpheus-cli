require 'yaml'
require 'json'
require 'morpheus/logging'
require 'morpheus/benchmarking'
require 'morpheus/cli/option_parser'
require 'morpheus/cli/cli_registry'
require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/credentials'
require 'morpheus/api/api_client'
require 'morpheus/cli/remote'
require 'morpheus/terminal'

module Morpheus
  module Cli
    # Module to be included by every CLI command so that commands get registered
    # This mixin defines a print and puts method, and delegates
    # todo: use delegate
    module CliCommand

      def self.included(klass)
        klass.send :include, Morpheus::Cli::PrintHelper
        klass.send :include, Morpheus::Benchmarking::HasBenchmarking
        klass.extend ClassMethods
        Morpheus::Cli::CliRegistry.add(klass, klass.command_name)
      end

      # the beginning of instance variables from optparse !

      # this setting makes it easy for the called to disable prompting
      attr_reader :no_prompt

      # @return [Morpheus::Terminal] the terminal this command is being executed inside of
      def my_terminal
        @my_terminal ||= Morpheus::Terminal.instance
      end

      # set the terminal this is running this command.
      # @param term [MorpheusTerminal] the terminal this command is assigned to
      # @return the Terminal this command is being executed inside of
      def my_terminal=(term)
        if !t.is_a?(Morpheus::Terminal)
          raise "CliCommand #{self.class} terminal= expects object of type Terminal and instead got a #{t.class}"
        end
        @my_terminal = t
      end


      # delegate :print, to: :my_terminal
      # delegate :puts, to: :my_terminal
      # or . . . bum  bum bummm
      # a paradigm shift away from include and use module functions instead.
      # module_function :print, puts
      # delegate :puts, to: :my_terminal
      
      def print(*msgs)
        my_terminal.stdout.print(*msgs)
      end

      def puts(*msgs)
        my_terminal.stdout.puts(*msgs)
      end

      def print_error(*msgs)
        my_terminal.stderr.print(*msgs)
      end

      def puts_error(*msgs)
        my_terminal.stderr.puts(*msgs)
      end

      # todo: customizable output color, other than cyan.
      # def terminal_fg
      # end
      # def cyan
      #   Term::ANSIColor.black
      # end

      # todo: use terminal.stdin
      # def readline(*msgs)
      #   @my_terminal.stdin.readline(*msgs)
      # end

      # todo: maybe...
      # disabled prompting for this command
      # def noninteractive()
      #   @no_prompt = true
      #   self
      # end

      # whether to prompt or not, this is true by default.
      def interactive?
        @no_prompt != true
      end

      def raise_command_error(msg)
        raise Morpheus::Cli::CommandError.new(msg)
      end

      # parse_id_list splits returns the given id_list with its values split on a comma
      #               your id values cannot contain a comma, atm...
      # @param id_list [String or Array of Strings]
      # @param delim [String] Default is a comma and any surrounding white space.
      # @return array of values
      def parse_id_list(id_list, delim=/\s*\,\s*/)
        [id_list].flatten.collect {|it| it ? it.to_s.split(delim) : nil }.flatten.compact
      end

      # Appends Array of OptionType definitions to an OptionParser instance
      # This adds an option like --fieldContext.fieldName="VALUE"
      # @param opts [OptionParser]
      # @param options [Hash] output map that is being constructed
      # @param option_types [Array] list of OptionType definitions to add
      # @return void, this modifies the opts in place.
      def build_option_type_options(opts, options, option_types=[])
        #opts.separator ""
        #opts.separator "Options:"
        options[:options] ||= {} # this is where these go..for now
        custom_options = options[:options]
        
        # add each one to the OptionParser
        option_types.each do |option_type|
          field_namespace = []
          field_name = option_type['fieldName'].to_s
          if field_name.empty?
            puts "Missing fieldName for option type: #{option_type}" if Morpheus::Logging.debug?
            next
          end
          
          if !option_type['fieldContext'].to_s.empty?
            option_type['fieldContext'].split(".").each do |ns|
              field_namespace << ns
            end
          end
          
          full_field_name = field_name
          if !field_namespace.empty?
            full_field_name = "#{field_namespace.join('.')}.#{field_name}"
          end

          description = "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{option_type['defaultValue'] ? ' Default: '+option_type['defaultValue'].to_s : ''}"
          if option_type['description']
            # description << "\n                                     #{option_type['description']}"
            description << " - #{option_type['description']}"
          end
          if option_type['helpBlock']
            description << "\n                                     #{option_type['helpBlock']}"
          end
          # description = option_type['description'].to_s
          # if option_type['defaultValue']
          #   description = "#{description} Default: #{option_type['defaultValue']}"
          # end
          # if option_type['required'] == true
          #   description = "(Required) #{description}"
          # end
          
          value_label = "VALUE"
          if option_type['placeHolder']
            value_label = option_type['placeHolder']
          elsif option_type['type'] == 'checkbox'
            value_label = 'on|off' # or.. true|false
          elsif option_type['type'] == 'number'
            value_label = 'NUMBER'
          # elsif option_type['type'] == 'select'
          #   value_label = 'SELECT'
          # elsif option['type'] == 'select'
          end
          opts.on("--#{full_field_name} #{value_label}", String, description) do |val|
            cur_namespace = custom_options
            field_namespace.each do |ns|
              next if ns.empty?
              cur_namespace[ns.to_s] ||= {}
              cur_namespace = cur_namespace[ns.to_s]
            end
            cur_namespace[field_name] = val
          end

          # todo: all the various types
          # number 
          # checkbox [on|off]
          # select for optionSource and selectOptions

        end
        opts
      end

      # appends to the passed OptionParser all the generic options
      # @param opts [OptionParser] the option parser object being constructed
      # @param options [Hash] the output Hash that is to being modified
      # @param includes [Array] which options to include eg. :options, :json, :remote
      # @return opts
      def build_common_options(opts, options, includes=[], excludes=[])
        #opts.separator ""
        # opts.separator "Common options:"
        option_keys = includes.clone
        # todo: support --quiet everywhere
        # turn on some options all the time..
        # unless command_name == "shell"
        #   option_keys << :quiet unless option_keys.include?(:quiet)
        # end

        # ensure commands can always access options[:options], until we can deprecate it...
        options[:options] ||= {}

        while (option_key = option_keys.shift) do
          case option_key.to_sym

          when :account
            opts.on('-a','--account ACCOUNT', "Account Name") do |val|
              options[:account_name] = val
            end
            opts.on('-A','--account-id ID', "Account ID") do |val|
              options[:account_id] = val
            end

          when :options
            options[:options] ||= {}
            opts.on( '-O', '--option OPTION', "Option in the format -O field=\"value\"" ) do |option|
              # todo: look ahead and parse ALL the option=value args after -O switch
              #custom_option_args = option.split('=')
              custom_option_args = option.sub(/\s?\=\s?/, '__OPTION_DELIM__').split('__OPTION_DELIM__')
              custom_options = options[:options]
              option_name_args = custom_option_args[0].split('.')
              if option_name_args.count > 1
                nested_options = custom_options
                option_name_args.each_with_index do |name_element,index|
                  if index < option_name_args.count - 1
                    nested_options[name_element] = nested_options[name_element] || {}
                    nested_options = nested_options[name_element]
                  else
                    val = custom_option_args[1]
                    if val.to_s[0] == '{' && val.to_s[-1] == '}'
                      begin
                        val = JSON.parse(val)
                      rescue
                        Morpheus::Logging::DarkPrinter.puts "Failed to parse option value '#{val}' as JSON" if Morpheus::Logging.debug?
                      end
                    end
                    nested_options[name_element] = val
                  end
                end
              else
                val = custom_option_args[1]
                if val.to_s[0] == '{' && val.to_s[-1] == '}'
                  begin
                    val = JSON.parse(val)
                  rescue
                    Morpheus::Logging::DarkPrinter.puts "Failed to parse option value '#{val}' as JSON" if Morpheus::Logging.debug?
                  end
                end
                custom_options[custom_option_args[0]] = val
              end
              # convert "true","on" and "false","off" to true and false
              unless options[:skip_booleanize]
                custom_options.booleanize!
              end
              options[:options] = custom_options
            end
            opts.on('-P','--prompt', "Always prompts. Use passed options as the default value.") do |val|
              options[:always_prompt] = true
              options[:options] ||= {}
              options[:options][:always_prompt] = true
            end
            opts.on('-N','--no-prompt', "Skip prompts. Use default values for all optional fields.") do |val|
              options[:no_prompt] = true
              options[:options] ||= {}
              options[:options][:no_prompt] = true
            end

          when :prompt
            opts.on('-P','--prompt', "Always prompts. Use passed options as the default value.") do |val|
              options[:always_prompt] = true
              options[:options] ||= {}
              options[:options][:always_prompt] = true
            end
            opts.on('-N','--no-prompt', "Skip prompts. Use default values for all optional fields.") do |val|
              options[:no_prompt] = true
              options[:options] ||= {}
              options[:options][:no_prompt] = true
            end

          when :payload
            opts.on('--payload FILE', String, "Payload from a local JSON or YAML file, skip all prompting") do |val|
              options[:payload_file] = val.to_s
              begin
                payload_file = File.expand_path(options[:payload_file])
                if !File.exists?(payload_file) || !File.file?(payload_file)
                  raise ::OptionParser::InvalidOption.new("File not found: #{payload_file}")
                  #return false
                end
                if payload_file =~ /\.ya?ml\Z/
                  options[:payload] = YAML.load_file(payload_file)
                else
                  options[:payload] = JSON.parse(File.read(payload_file))
                end
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload file: #{payload_file} Error: #{ex.message}")
              end
            end
            opts.on('--payload-dir DIRECTORY', String, "Payload from a local directory containing 1-N JSON or YAML files, skip all prompting") do |val|
              options[:payload_dir] = val.to_s
              payload_dir = File.expand_path(options[:payload_dir])
              if !Dir.exists?(payload_dir) || !File.directory?(payload_dir)
                raise ::OptionParser::InvalidOption.new("Directory not found: #{payload_dir}")
              end
              payload = {}
              begin
                merged_payload = {}
                payload_files = []
                payload_files += Dir["#{payload_dir}/*.json"]
                payload_files += Dir["#{payload_dir}/*.yml"]
                payload_files += Dir["#{payload_dir}/*.yaml"]
                if payload_files.empty?
                  raise ::OptionParser::InvalidOption.new("No .json/yaml files found in config directory: #{payload_dir}")
                end
                payload_files.each do |payload_file|
                  Morpheus::Logging::DarkPrinter.puts "parsing payload file: #{payload_file}" if Morpheus::Logging.debug?
                  config_payload = {}
                  if payload_file =~ /\.ya?ml\Z/
                    config_payload = YAML.load_file(payload_file)
                  else
                    config_payload = JSON.parse(File.read(payload_file))
                  end
                  merged_payload.deep_merge!(config_payload)
                end
                options[:payload] = merged_payload
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload file: #{payload_file} Error: #{ex.message}")
              end
            end
            opts.on('--payload-json JSON', String, "Payload JSON, skip all prompting") do |val|
              begin
                options[:payload] = JSON.parse(val.to_s)
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload as JSON. Error: #{ex.message}")
              end
            end
            opts.on('--payload-yaml YAML', String, "Payload YAML, skip all prompting") do |val|
              begin
                options[:payload] = YAML.load(val.to_s)
              rescue => ex
                raise ::OptionParser::InvalidOption.new("Failed to parse payload as YAML. Error: #{ex.message}")
              end
            end

          when :list
            opts.on( '-m', '--max MAX', "Max Results" ) do |val|
              max = val.to_i
              if max <= 0
                raise ::OptionParser::InvalidArgument.new("must be a positive integer")
              end
              options[:max] = max
            end

            opts.on( '-o', '--offset OFFSET', "Offset Results" ) do |val|
              offset = val.to_i
              if offset <= 0
                raise ::OptionParser::InvalidArgument.new("must be a positive integer")
              end
              options[:offset] = offset
            end

            opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
              options[:phrase] = phrase
            end

            opts.on( '-S', '--sort ORDER', "Sort Order. DIRECTION may be included as \"ORDER [asc|desc]\"." ) do |v|
              v_parts = v.to_s.split(" ")
              if v_parts.size > 1
                options[:sort] = v_parts[0]
                options[:direction] = (v_parts[1].strip == "desc") ? "desc" : "asc"
              else
                options[:sort] = v
              end
            end

            opts.on( '-D', '--desc', "Reverse Sort Order" ) do |v|
              options[:direction] = "desc"
            end

            # arbitrary query parameters in the format -Q "category=web&phrase=nginx"
            # opts.on( '-Q', '--query PARAMS', "Query parameters. PARAMS format is 'phrase=foobar&category=web'" ) do |val|
            #   options[:query_filters_raw] = val
            #   options[:query_filters] = {}
            #   # todo: smarter parsing
            #   val.split('&').each do |filter| 
            #     k, v = filter.split('=')
            #     # allow "woot:true instead of woot=true"
            #     if (k.include?(":") && v == nil)
            #       k, v = k.split(":")
            #     end
            #     if (!k.to_s.empty?)
            #       options[:query_filters][k.to_s.strip] = v.to_s.strip
            #     end
            #   end
            # end

          when :query, :query_filters
            # arbitrary query parameters in the format -Q "category=web&phrase=nginx"
            opts.on( '-Q', '--query PARAMS', "Query parameters. PARAMS format is 'phrase=foobar&category=web'" ) do |val|
              options[:query_filters_raw] = val
              options[:query_filters] = {}
              # todo: smarter parsing
              val.split('&').each do |filter| 
                k, v = filter.split('=')
                # allow "woot:true instead of woot=true"
                if (k.include?(":") && v == nil)
                  k, v = k.split(":")
                end
                if (!k.to_s.empty?)
                  if options[:query_filters].key?(k.to_s.strip)
                    cur_val = options[:query_filters][k.to_s.strip]
                    if cur_val.instance_of?(Array)
                      options[:query_filters][k.to_s.strip] << v.to_s.strip
                    else
                      options[:query_filters][k.to_s.strip] = [cur_val, v.to_s.strip]
                    end
                  else
                    options[:query_filters][k.to_s.strip] = v.to_s.strip
                  end
                end
              end
            end

          when :last_updated
            # opts.on("--last-updated TIME", Time, "Filter by gte last updated") do |time|
            opts.on("--last-updated TIME", String, "Filter by Last Updated (gte)") do |time|
              begin
                options[:lastUpdated] = parse_time(time)
              rescue => e
                raise OptionParser::InvalidArgument.new "Failed to parse time '#{time}'. Error: #{e}"
              end
            end

          when :remote
            opts.on( '-r', '--remote REMOTE', "Remote name. The current remote is used by default." ) do |val|
              options[:remote] = val
            end
            opts.on( nil, '--remote-url URL', "Remote url. The current remote url is used by default." ) do |val|
              options[:remote_url] = val
            end
            opts.on( '-T', '--token TOKEN', "Access token for authentication with --remote. Saved credentials are used by default." ) do |val|
              options[:remote_token] = val
            end unless excludes.include?(:remote_token)
            opts.on( '-U', '--username USERNAME', "Username for authentication." ) do |val|
              options[:remote_username] = val
            end unless excludes.include?(:remote_username)
            opts.on( '-P', '--password PASSWORD', "Password for authentication." ) do |val|
              options[:remote_password] = val
            end unless excludes.include?(:remote_password)

            # todo: also require this for talking to plain old HTTP
            opts.on('-I','--insecure', "Allow insecure HTTPS communication.  i.e. bad SSL certificate.") do |val|
              options[:insecure] = true
              Morpheus::RestClient.enable_ssl_verification = false
            end
          
          #when :header, :headers
            opts.on( '-H', '--header HEADER', "Additional HTTP header to include with requests." ) do |val|
              options[:headers] ||= {}
              # header_list = val.to_s.split(',')
              header_list = [val.to_s]
              header_list.each do |h|
                header_parts = val.to_s.split(":")
                header_key, header_value = header_parts[0], header_parts[1..-1].join(":").strip
                if header_parts.size() < 2
                  header_parts = val.to_s.split("=")
                  header_key, header_value = header_parts[0], header_parts[1..-1].join("=").strip
                end
                if header_parts.size() < 2
                  raise_command_error "Invalid HEADER value '#{val}'. HEADER should contain a key and a value. eg. -H 'X-Morpheus-Lease: $MORPHEUS_LEASE_TOKEN'"
                end
                options[:headers][header_key] = header_value
              end
            end
            # opts.add_hidden_option('-H') if opts.is_a?(Morpheus::Cli::OptionParser)
            # opts.add_hidden_option('--header') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.add_hidden_option('--headers') if opts.is_a?(Morpheus::Cli::OptionParser)

          #when :timeout
            opts.on( '--timeout SECONDS', "Timeout for api requests. Default is typically 30 seconds." ) do |val|
              options[:timeout] = val ? val.to_f : nil
            end
            # opts.add_hidden_option('--timeout') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :auto_confirm
            opts.on( '-y', '--yes', "Auto Confirm" ) do
              options[:yes] = true
            end

          when :json
            opts.on('-j','--json', "JSON Output") do
              options[:json] = true
              options[:format] = :json
            end

            opts.on('--json-raw', String, "JSON Output that is not so pretty.") do |val|
              options[:json] = true
              options[:format] = :json
              options[:pretty_json] = false
            end
            opts.add_hidden_option('json-raw') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :yaml
            opts.on(nil, '--yaml', "YAML Output") do
              options[:yaml] = true
              options[:format] = :yaml
            end
            opts.on(nil, '--yml', "alias for --yaml") do
              options[:yaml] = true
              options[:format] = :yaml
            end
            opts.add_hidden_option('yml') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :csv
            opts.on(nil, '--csv', "CSV Output") do
              options[:csv] = true
              options[:format] = :csv
              #options[:csv_delim] = options[:csv_delim] || ","
            end

            opts.on('--csv-delim CHAR', String, "Delimiter for CSV Output values. Default: ','") do |val|
              options[:csv] = true
              options[:format] = :csv
              val = val.gsub("\\n", "\n").gsub("\\r", "\r").gsub("\\t", "\t") if val.include?("\\")
              options[:csv_delim] = val
            end

            opts.on('--csv-newline [CHAR]', String, "Delimiter for CSV Output rows. Default: '\\n'") do |val|
              options[:csv] = true
              options[:format] = :csv
              if val == "no" || val == "none"
                options[:csv_newline] = ""
              else
                val = val.gsub("\\n", "\n").gsub("\\r", "\r").gsub("\\t", "\t") if val.include?("\\")
                options[:csv_newline] = val
              end
            end

            opts.on(nil, '--csv-quotes', "Wrap CSV values with \". Default: false") do
              options[:csv] = true
              options[:format] = :csv
              options[:csv_quotes] = true
            end

            opts.on(nil, '--csv-no-header', "Exclude header for CSV Output.") do
              options[:csv] = true
              options[:format] = :csv
              options[:csv_no_header] = true
            end

          when :fields
            opts.on('-F', '--fields x,y,z', Array, "Filter Output to a limited set of fields. Default is all fields.") do |val|
              options[:include_fields] = val
            end
            opts.on(nil, '--all-fields', "Show all fields. Useful for showing hidden columns on wide tables.") do
              options[:all_fields] = true
            end
            opts.add_hidden_option('--all-fields') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :thin
            opts.on( '--thin', '--thin', "Format headers and columns with thin borders." ) do |val|
              options[:border_style] = :thin
            end
            
          

          when :dry_run
            opts.on('-d','--dry-run', "Dry Run, print the API request instead of executing it") do
              # todo: this should print after parsing obv..
              # need a hook after parse! or a standard_handle(options) { ... } paradigm
              # either that or hook it up in every command somehow, maybe a hook on connect()
              #puts "#{cyan}#{dark} #=> DRY RUN#{reset}"
              # don't print this for --json combined with -d
              # print once and dont munge json
              if !options[:curl] && !options[:json]
                puts "#{cyan}#{bold}#{dark}DRY RUN#{reset}"
              end
              options[:dry_run] = true
            end
            opts.on(nil,'--curl', "Dry Run to output API request as a curl command.") do
              # print once and dont munge json
              if !options[:dry_run] && !options[:json]
                puts "#{cyan}#{bold}#{dark}DRY RUN#{reset}"
              end
              options[:dry_run] = true
              options[:curl] = true
            end
            opts.on(nil,'--scrub', "Mask secrets in output, such as the Authorization header. For use with --curl and --dry-run.") do
              options[:scrub] = true
            end
            # dry run comes with hidden outfile options
            #opts.add_hidden_option('--scrub') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on('--out FILE', String, "Write standard output to a file instead of the terminal.") do |val|
              # could validate directory is writable..
              options[:outfile] = val
            end
            opts.add_hidden_option('--out') if opts.is_a?(Morpheus::Cli::OptionParser)
            opts.on('--overwrite', '--overwrite', "Overwrite output file if it already exists.") do
              options[:overwrite] = true
            end
            opts.add_hidden_option('--overwrite') if opts.is_a?(Morpheus::Cli::OptionParser)

          when :outfile
            opts.on('--out FILE', String, "Write standard output to a file instead of the terminal.") do |val|
              options[:outfile] = val
            end
            opts.on('--overwrite', '--overwrite', "Overwrite output file if it already exists.") do |val|
              options[:overwrite] = true
            end
          when :quiet
            opts.on('-q','--quiet', "No Output, do not print to stdout") do
              options[:quiet] = true
            end

          else
            raise "Unknown common_option key: #{option_key}"
          end
        end

        # options that are always included

        # always support thin, but hidden because mostly not hooked up at the moment...
        unless includes.include?(:thin)
          opts.on( '--thin', '--thin', "Format headers and columns with thin borders." ) do |val|
            options[:border_style] = :thin
          end
          opts.add_hidden_option('--thin') if opts.is_a?(Morpheus::Cli::OptionParser)
        end

        # disable ANSI coloring
        opts.on('-C','--nocolor', "Disable ANSI coloring") do
          Term::ANSIColor::coloring = false
        end


        # Benchmark this command?
        opts.on('-B','--benchmark', "Print benchmark time after the command is finished.") do
          options[:benchmark] = true
          # this is hacky, but working!  
          # shell handles returning to false
          #Morpheus::Benchmarking.enabled = true
          #my_terminal.benchmarking = true
          #start_benchmark(args.join(' '))
          # ok it happens outside of handle() alltogether..
          # wow, simplify me plz
        end

        opts.on('-V','--debug', "Print extra output for debugging.") do
          options[:debug] = true
          Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
          ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
          # perhaps...
          # create a new logger instance just for this command instance
          # this way we don't elevate the global level for subsequent commands in a shell
          # @logger = Morpheus::Logging::Logger.new(STDOUT)
          # if !@logger.debug?
          #   @logger.log_level = Morpheus::Logging::Logger::DEBUG
          # end
        end

        opts.on('-h', '--help', "Print this help" ) do
          puts opts
          exit # return 0 maybe?
        end

        opts
      end

      def command_name
        self.class.command_name
      end

      def subcommands
        self.class.subcommands
      end

      def subcommand_aliases
        self.class.subcommand_aliases
      end

      def default_subcommand
        self.class.default_subcommand
      end

      def default_refresh_interval
        self.class.default_refresh_interval
      end

      def usage
        if !subcommands.empty?
          "Usage: morpheus #{command_name} [command] [options]"
        else
          "Usage: morpheus #{command_name} [options]"
        end
      end

      def my_help_command
        "morpheus #{command_name} --help"
      end

      def subcommand_usage(*extra)
        calling_method = caller[0][/`([^']*)'/, 1].to_s.sub('block in ', '')
        subcommand_name = subcommands.key(calling_method)
        extra = extra.flatten
        if !subcommand_name.empty? && extra.first == subcommand_name
          extra.shift
        end
        #extra = ["[options]"] if extra.empty?
        "Usage: morpheus #{command_name} #{subcommand_name} #{extra.join(' ')}".squeeze(' ').strip
      end

      # a string to describe the usage of your command
      # this is what the --help option
      # feel free to override this in your commands
      def full_command_usage
        out = ""
        out << usage.to_s.strip if usage
        out << "\n"
        if !subcommands.empty?
          out << "Commands:"
          out << "\n"
          subcommands.sort.each {|cmd, method|
            out << "\t#{cmd.to_s}\n"
          }
        end
        # out << "\n"
        out
      end

      # a default handler
      def handle_subcommand(args)
        commands = subcommands
        if subcommands.empty?
          raise "#{self.class} has no available subcommands"
        end
        # meh, could deprecate and make subcommand define handle() itself
        # if args.count == 0 && default_subcommand
        #   # p "using default subcommand #{default_subcommand}"
        #   return self.send(default_subcommand, args || [])
        # end
        subcommand_name = args[0]
        if args.empty?
          print_error Morpheus::Terminal.angry_prompt
          puts_error "[command] argument is required"
          puts full_command_usage
          exit 127
        end
        if args[0] == "-h" || args[0] == "--help" || args[0] == "help"
          puts full_command_usage
          return 0
        end
        if subcommand_aliases[subcommand_name]
          subcommand_name = subcommand_aliases[subcommand_name]
        end
        cmd_method = subcommands[subcommand_name]
        if !cmd_method
          print_error Morpheus::Terminal.angry_prompt
          #puts_error "'#{subcommand_name}' is not recognized. See '#{my_help_command}'"
          puts_error "'#{subcommand_name}' is not recognized.\n#{full_command_usage}"
          return 127
        end
        self.send(cmd_method, args[1..-1])
      end

      def handle(args)
        raise "#{self} has not defined handle()!"
      end

      # executes block with each argument in the list
      # @return [0|1] 0 if they were all successful, else 1
      def run_command_for_each_arg(args, &block)
        cmd_results = []
        args.each do |arg|
          begin
            cur_result = yield arg
          rescue SystemExit => err
            cur_result = err.success? ? 0 : 1
          end
          cmd_results << cur_result
        end
        # find a bad result and return it
        cmd_results = cmd_results.collect do |cmd_result| 
          if cmd_result.is_a?(Array)
            cmd_result
          else
            [cmd_result, nil]
          end
        end
        failed_result = cmd_results.find {|cmd_result| cmd_result[0] == false || (cmd_result[0].is_a?(Integer) && cmd_result[0] != 0) }
        return failed_result ? failed_result : cmd_results.last
      end

      # This supports the simple remote option eg. `instances add --remote "qa"`
      # It will establish a connection to the pre-configured appliance named "qa"
      # The calling command can populate @appliances and/or @appliance_name
      # Otherwise, the current active appliance is used...
      # This returns a new instance of Morpheus::APIClient (and sets @access_token, and @appliance)
      # Your command should be ready to make api requests after this.
      def establish_remote_appliance_connection(options)
        # todo: probably refactor and don't rely on this method to set these instance vars
        @appliance_name, @appliance_url, @access_token = nil, nil, nil
        @api_client = nil

        appliance = nil # @appliance..why not? laff
        if options[:remote]
          appliance = ::Morpheus::Cli::Remote.load_remote(options[:remote])
          if !appliance
            if ::Morpheus::Cli::Remote.appliances.empty?
              raise_command_error "You have no appliances configured. See the `remote add` command."
            else
              raise_command_error "Remote appliance not found by the name '#{options[:remote]}'"
            end
          end
        else
          appliance = ::Morpheus::Cli::Remote.load_active_remote()
          if !appliance
            if ::Morpheus::Cli::Remote.appliances.empty?
              raise_command_error "You have no appliances configured. See the `remote add` command."
            else
              raise_command_error "No current appliance, see `remote use`."
            end
          end
        end
        @appliance_name = appliance[:name]
        @appliance_url = appliance[:host] || appliance[:url] # it's :host in the YAML..heh

        # instead of toggling this global value
        # this should just be an attribute of the api client
        # for now, this fixes the issue where passing --insecure or --remote
        # would then apply to all subsequent commands...
        if !Morpheus::Cli::Shell.insecure
          if options[:insecure]
            Morpheus::RestClient.enable_ssl_verification = false
          else
            if appliance[:insecure] && Morpheus::RestClient.ssl_verification_enabled?
              Morpheus::RestClient.enable_ssl_verification = false
            elsif !appliance[:insecure] && !Morpheus::RestClient.ssl_verification_enabled?
              Morpheus::RestClient.enable_ssl_verification = true
            end
          end
        end

        # todo: support old way of accepting --username and --password on the command line
        # it's probably better not to do that tho, just so it stays out of history files
        

        # if !@appliance_name && !@appliance_url
        #   raise_command_error "Please specify a remote appliance with -r or see the command `remote use`"
        # end

        Morpheus::Logging::DarkPrinter.puts "establishing connection to [#{@appliance_name}] #{@appliance_url}" if options[:debug]
        #puts "#{dark} #=> establishing connection to [#{@appliance_name}] #{@appliance_url}#{reset}\n" if options[:debug]


        # ok, get some credentials.
        # this prompts for username, password  without options[:no_prompt]
        # uses saved credentials by default.
        # passing --remote-url or --token or --username will skip loading saved credentials and trigger prompting
        if options[:remote_token]
          @access_token = options[:remote_token]
        else
          credentials = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url)
          # @wallet = credentials.load_saved_credentials()
          # @wallet = credentials.request_credentials(options)
          if options[:remote_token]
            @wallet = credentials.request_credentials(options, false)
          elsif options[:remote_url] || options[:remote_username]
            @wallet = credentials.request_credentials(options, false)
          else
            #@wallet = credentials.request_credentials(options)
            @wallet = credentials.load_saved_credentials()
          end
          @access_token = @wallet ? @wallet['access_token'] : nil
          # if @access_token.to_s.empty?
          #   unless options[:no_prompt]
          #     @wallet = credentials.request_credentials(options)
          #     @access_token = @wallet ? @wallet['access_token'] : nil
          #   end
          # end
          # bail if we got nothing still
          unless options[:skip_verify_access_token]
            verify_access_token!
          end
        end

        # ok, connect to the appliance.. actually this just instantiates an ApiClient
        api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
        @api_client = api_client # meh, just return w/o setting instance attrs
        return api_client
      end

      def verify_access_token!
        if @access_token.empty?
          raise_command_error "Unable to acquire access token. Please verify your credentials and try again."
        end
        true
      end

      # parse the parameters provided by the common :list options
      # returns Hash of params the format {"phrase": => "foobar", "max": 100}
      def parse_list_options(options={})
        list_params = {}
        [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
          if options.key?(k)
            list_params[k.to_s] = options[k]
          elsif options.key?(k.to_s)
            list_params[k.to_s] = options[k.to_s]
          end
        end
        # arbitrary filters
        if options[:query_filters]
          options[:query_filters].each do |k, v|
            if k
              list_params[k] = v
            end
          end
        end
        return list_params
      end

      # parse the subtitles provided by the common :list options
      # returns Array of subtitles as strings in the format ["Phrase: blah", "Max: 100"]
      def parse_list_subtitles(options={})
        subtitles = []
        list_params = {}
        [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
          if options.key?(k)
            subtitles << "#{k.to_s}: #{options[k]}"
          elsif options.key?(k.to_s)
            subtitles << "#{k.to_s}: #{options[k.to_s]}"
          end
        end
        # arbitrary filters
        if options[:query_filters]
          formatted_filters = options[:query_filters].collect {|k,v| "#{k.to_s}=#{v}" }.join('&')
          subtitles << "Query: #{formatted_filters}"
          # options[:query_filters].each do |k, v|
          #   subtitles << "#{k.to_s}: #{v}"
          # end
        end
        return subtitles
      end

      # basic rendering for options :json, :yaml, :csv, :fields, and :outfile
      # returns the string rendered, or nil if nothing was rendered.
      def render_with_format(json_response, options, object_key=nil)
        output = nil
        if options[:json]
          output = as_json(json_response, options, object_key)
        elsif options[:yaml]
          output = as_yaml(json_response, options, object_key)
        elsif options[:csv]
          row = object_key ? json_response[object_key] : json_response
          if row.is_a?(Array)
            output = records_as_csv(row, options)
          else
            output = records_as_csv([row], options)
          end
        end
        if output
          if options[:outfile]
            print_to_file(output, options[:outfile], options[:overwrite])
          else
            puts output
          end
        end
        return output
      end

      module ClassMethods

        def set_command_name(cmd_name)
          @command_name = cmd_name
          Morpheus::Cli::CliRegistry.add(self, self.command_name)
        end

        def default_command_name
          class_name = self.name.split('::')[-1]
          #class_name.sub!(/Command$/, '')
          Morpheus::Cli::CliRegistry.cli_ize(class_name)
        end
        
        def command_name
          @command_name ||= default_command_name
          @command_name
        end

        def set_command_hidden(val=true)
          @hidden_command = val
        end
        # alias :command_name= :set_command_name

        def hidden_command
          !!@hidden_command
        end

        def command_description
          @command_description
        end

        def set_command_description(val)
          @command_description = val
        end
        # alias :command_description= :set_command_description

        def default_refresh_interval
          @default_refresh_interval ||= 30
        end

        def set_default_refresh_interval(seconds)
          @default_refresh_interval = seconds
        end
        #alias :default_refresh_interval= :set_default_refresh_interval
        

        # construct map of command name => instance method
        def register_subcommands(*cmds)
          @subcommands ||= {}
          cmds.flatten.each {|cmd| 
            if cmd.is_a?(Hash)
              cmd.each {|k,v| 
                # @subcommands[k] = v
                add_subcommand(k.to_s, v.to_s)
              }
            elsif cmd.is_a?(Array) 
              cmd.each {|it| register_subcommands(it) }
            elsif cmd.is_a?(String) || cmd.is_a?(Symbol)
              #k = Morpheus::Cli::CliRegistry.cli_ize(cmd)
              k = cmd.to_s.gsub('_', '-')
              v = cmd.to_s.gsub('-', '_')
              register_subcommands({(k) => v})
            else
              raise "Unable to register command of type: #{cmd.class} #{cmd}"
            end
          }
          return
        end

        def set_default_subcommand(cmd)
          @default_subcommand = cmd
        end

        def default_subcommand
          @default_subcommand
        end

        def subcommands
          @subcommands ||= {}
        end

        def has_subcommand?(cmd_name)
          return false if cmd_name.empty?
          @subcommands && @subcommands[cmd_name.to_s]
        end

        def add_subcommand(cmd_name, method)
          @subcommands ||= {}
          @subcommands[cmd_name.to_s] = method
        end

        def remove_subcommand(cmd_name)
          @subcommands ||= {}
          @subcommands.delete(cmd_name.to_s)
        end

        # register an alias for a command
        def alias_subcommand(alias_cmd_name, cmd_name)
          add_subcommand_alias(alias_cmd_name.to_s, cmd_name.to_s.gsub('_', '-'))
          return
        end

        def subcommand_aliases
          @subcommand_aliases ||= {}
        end

        def add_subcommand_alias(alias_cmd_name, cmd_name)
          @subcommand_aliases ||= {}
          @subcommand_aliases[alias_cmd_name.to_s] = cmd_name
        end

        def remove_subcommand_alias(alias_cmd_name)
          @subcommand_aliases ||= {}
          @subcommand_aliases.delete(alias_cmd_name.to_s)
        end

      end
    end
  end
end
