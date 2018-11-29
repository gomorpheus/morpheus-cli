require 'yaml'
require 'json'
require 'morpheus/logging'
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
      def build_common_options(opts, options, includes=[])
        #opts.separator ""
        # opts.separator "Common options:"
        includes = includes.clone
        while (option_key = includes.shift) do
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
                    nested_options[name_element] = custom_option_args[1]
                  end
                end
              else
                custom_options[custom_option_args[0]] = custom_option_args[1]
              end
              # convert "true","on" and "false","off" to true and false
              custom_options.booleanize!
              options[:options] = custom_options
            end
            opts.on('-N','--no-prompt', "Skip prompts. Use default values for all optional fields.") do |val|
              options[:no_prompt] = true
              # ew, stored in here for now because options[:options] is what is passed into OptionTypes.prompt() everywhere!
              options[:options] ||= {}
              options[:options][:no_prompt] = true
            end

          when :noprompt
            opts.on('-N','--no-prompt', "Skip prompts. Use default values for all optional fields.") do |val|
              options[:no_prompt] = true
              # ew, stored in here for now because options[:options] is what is passed into OptionTypes.prompt() everywhere!
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
            opts.on( '-m', '--max MAX', "Max Results" ) do |max|
              options[:max] = max.to_i
            end

            opts.on( '-o', '--offset OFFSET', "Offset Results" ) do |offset|
              options[:offset] = offset.to_i.abs
            end

            opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
              options[:phrase] = phrase
            end

            opts.on( '-S', '--sort ORDER', "Sort Order" ) do |v|
              options[:sort] = v
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

            # this is the only option now... 
            # first, you must do `remote use [appliance]`
            opts.on( '-r', '--remote REMOTE', "Remote Appliance Name to use for this command. The active appliance is used by default." ) do |val|
              options[:remote] = val
            end

            # todo: also require this for talking to plain old HTTP
            opts.on('-I','--insecure', "Allow insecure HTTPS communication.  i.e. bad SSL certificate.") do |val|
              options[:insecure] = true
              Morpheus::RestClient.enable_ssl_verification = false
            end

            opts.on( '-T', '--token ACCESS_TOKEN', "Access Token for api requests. While authenticated to a remote, the current saved credentials are used." ) do |remote|
              options[:remote_token] = remote
            end

            # skipping the rest of this for now..

            next

            # opts.on( '-r', '--remote REMOTE', "Remote Appliance" ) do |remote|
            #   options[:remote] = remote
            # end

            opts.on( '-U', '--url REMOTE', "API Url" ) do |remote|
              options[:remote_url] = remote
            end

            opts.on( '-u', '--username USERNAME', "Username" ) do |remote|
              options[:remote_username] = remote
            end

            opts.on( '-p', '--password PASSWORD', "Password" ) do |remote|
              options[:remote_password] = remote
            end

            opts.on( '-T', '--token ACCESS_TOKEN', "Access Token" ) do |remote|
              options[:remote_token] = remote
            end
            
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

          when :dry_run
            opts.on('-d','--dry-run', "Dry Run, print the API request instead of executing it") do
              options[:dry_run] = true
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

        # disable ANSI coloring
        opts.on('-C','--nocolor', "Disable ANSI coloring") do
          Term::ANSIColor::coloring = false
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

        opts.on('-h', '--help', "Prints this help" ) do
          puts opts
          exit
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
          puts_error "'#{subcommand_name}' is not a morpheus #{self.command_name} command. See '#{my_help_command}'"
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
        failed_cmd = cmd_results.find {|cmd_result| cmd_result == false || (cmd_result.is_a?(Integer) && cmd_result != 0) }
        return failed_cmd ? failed_cmd : 0
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

        
        # punt.. and just allow passing an access token instead for now..
        # this skips saving to the appliances file and all that..
        if options[:token]
          @access_token = options[:token]
        end

        # ok, get some credentials.
        # this prompts for username, password  without options[:no_prompt]
        # used saved credentials please
        @api_credentials = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url)
        if options[:remote_token]
          @access_token = options[:remote_token]
        else
          @access_token = @api_credentials.load_saved_credentials()
          if @access_token.to_s.empty?
            unless options[:no_prompt]
              @access_token = @api_credentials.request_credentials(options)
            end
          end
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

      module ClassMethods

        def set_command_name(cmd_name)
          @command_name = cmd_name
          Morpheus::Cli::CliRegistry.add(self, self.command_name)
        end

        def default_command_name
          class_name = self.name.split('::')[-1]
          class_name.sub!(/Command$/, '')
          Morpheus::Cli::CliRegistry.cli_ize(class_name)
        end
        
        def command_name
          @command_name ||= default_command_name
          @command_name
        end

        def set_command_hidden(val=true)
          @hidden_command = val
        end
        
        def hidden_command
          !!@hidden_command
        end

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
