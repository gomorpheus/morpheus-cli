require 'morpheus/cli/cli_registry'
require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/credentials'
require 'morpheus/api/api_client'
require 'morpheus/cli/remote'

module Morpheus
	module Cli
		# Module to be included by every CLI command so that commands get registered
		module CliCommand

			def self.included(klass)
				klass.send :include, Morpheus::Cli::PrintHelper
				klass.extend ClassMethods
				Morpheus::Cli::CliRegistry.add(klass, klass.command_name)
			end

			def build_common_options(opts, options, includes=[])
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
						opts.on( '-O', '--option OPTION', "Option in the format var=\"value\"" ) do |option|
							custom_option_args = option.split('=')
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
														options[:options] = custom_options
						end
						opts.on('-N','--no-prompt', "Skip prompts. Use default values for all optional fields.") do |val|
							options[:no_prompt] = true
							# ew, stored in here for now because options[:options] is what is passed into OptionTypes.prompt() everywhere!
							options[:options] ||= {}
							options[:options][:no_prompt] = true
						end
					when :list
												opts.on( '-m', '--max MAX', "Max Results" ) do |max|
							options[:max] = max.to_i
						end

						opts.on( '-o', '--offset OFFSET', "Offset Results" ) do |offset|
							options[:offset] = offset.to_i
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

					when :remote

						# this is the only option now... 
						# first, you must do `remote use [appliance]`
						opts.on( '-r', '--remote REMOTE', "Remote Appliance Name to use for this command. The current appliance is used by default." ) do |val|
							options[:remote] = val
							options[:non_active_remote] = true # unused
						end

						# skipping the rest of this for now..
						next

						opts.on( '-r', '--remote REMOTE', "Remote Appliance" ) do |remote|
							options[:remote] = remote
						end

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
						opts.on('-j','--json', "JSON Output") do |json|
							options[:json] = true
						end

					when :dry_run
						opts.on('-d','--dry-run', "Dry Run, print the API request instead of executing it") do |json|
							options[:dry_run] = true
						end
											when :quiet
						opts.on('-q','--quiet', "No Output, when successful") do |json|
							options[:quiet] = true
						end

					else
						raise "Unknown common_option key: #{option_key}"
					end
				end

				# options that are always included
				opts.on('-C','--nocolor', "Disable ANSI coloring") do
					Term::ANSIColor::coloring = false
				end

				opts.on('-V','--debug', "Print extra output for debugging. ") do |json|
					options[:debug] = true
					# this is handled upstream for now...
					# Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
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

			def usage
				if !subcommands.empty?
					"Usage: morpheus #{command_name} [command] [options]"
				else
					"Usage: morpheus #{command_name} [options]"
				end
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

			def print_usage()
				puts usage
				if !subcommands.empty?
					puts "Commands:"
					subcommands.sort.each {|cmd, method|
						puts "\t#{cmd.to_s}"
					}
				end
			end

			# a default handler
			def handle_subcommand(args)
				commands = subcommands
				if subcommands.empty?
					raise "#{self.class} has no available subcommands"
				end
				cmd_name = args[0]
				if subcommand_aliases[cmd_name]
					cmd_name = subcommand_aliases[cmd_name]
				end
				cmd_method = subcommands[cmd_name]
				if cmd_name && !cmd_method
					#puts "unknown command '#{cmd_name}'"
				end
				if !cmd_method
					print_usage
					exit 127
				end
				self.send(cmd_method, args[1..-1])
			end

			def handle(args)
				raise "#{self} has not defined handle()!"
			end

			# This supports the simple remote option eg. `instances add --remote "qa"`
			# It will establish a connection to the pre-configured appliance named "qa"
			# The calling command needs to populate @appliances and/or @appliance_name
			# This returns a new instance of Morpheus::APIClient (and sets @access_token, and @appliance)
			# Your command should be ready to make api requests after this.
			# todo: probably don't exit here, just return nil or raise
			def establish_remote_appliance_connection(options)
				@appliances ||= ::Morpheus::Cli::Remote.load_appliance_file
				if !@appliance_name
					@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
				end

				# todo: support old way of accepting --username and --password on the command line
				# it's probably better not to do that tho, just so it stays out of history files

				# use a specific remote appliance by name
				if options[:remote]
					@appliance_name = options[:remote].to_sym rescue nil
					if !@appliances
						print_red_alert "You have no appliances configured. See the `remote add` command."
						exit 1
					end
					found_appliance = @appliances[@appliance_name.to_sym]
					if !found_appliance
						print_red_alert "You have no appliance named '#{@appliance_name}' configured. See the `remote add` command."
						exit 1
					end
					@appliance = found_appliance
					@appliance_name = @appliance_name
					@appliance_url = @appliance[:host]
					if options[:debug]
						print dark,"# => Using remote appliance [#{@appliance_name}] #{@appliance_url}",reset,"\n" if !options[:quiet]
					end
				else
					#@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
				end

				if !@appliance_name
					print_red_alert "No active appliance found. See the `remote use` command."
					exit 1
				end
								# ok, get some credentials.
				# this prompts for username, password
				@access_token = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).request_credentials(options)
								# bail if we got nothing
				if @access_token.empty?
					print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
					exit 1
				end

				# ok, connect to the appliance.. actually this just instantiates an ApiClient
				# setup our api client for all including commands to use.
				@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
				return @api_client
			end

			module ClassMethods

				def set_command_name(cmd_name)
					@command_name = cmd_name
					Morpheus::Cli::CliRegistry.add(self, self.command_name)
				end

				def default_command_name
					Morpheus::Cli::CliRegistry.cli_ize(self.name.split('::')[-1])
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
