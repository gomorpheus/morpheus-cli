
module Morpheus
	module Cli
		class CliRegistry

			def initialize
				@commands = {} # this is command => Class that includes ::CliCommand
				@aliases = {} # this is alias => String full input string
			end
						class << self
								def instance
					@instance ||= CliRegistry.new
				end

				def exec(command_name, args)
					exec_command(command_name, args)
				end

				def exec_command(command_name, args)
					#puts "exec_command(#{command_name}, #{args})"
					Term::ANSIColor::coloring = STDOUT.isatty
					found_alias_command = instance.get_alias(command_name)
					if found_alias_command
						exec_alias(command_name, args)
					else
						#puts "running regular command #{command_name} with arguments #{args.join(' ')}"
						instance.get(command_name).new.handle(args)
					end
				end

				def exec_alias(alias_name, args)
					#puts "exec_alias(#{alias_name}, #{args})"
					found_alias_command = instance.get_alias(alias_name)
					# support aliases of multiple commands, semicolon delimiter
					all_commands = found_alias_command.gsub(/(\;)(?=(?:[^"']|"[^'"]*")*$)/, '__CMDDELIM__').split('__CMDDELIM__').collect {|it| it.to_s.strip }.select {|it| !it.empty?  }.compact
					puts "alias #{alias_name} all_commands is : #{all_commands.inspect}"
					all_commands.each do |a_command_string|
						alias_args = a_command_string.to_s.split(/\s+/) # or just ' '
						command_name = alias_args.shift
						command_args = alias_args + args
						if command_name == alias_name
							# needs to be better than this
							print Term::ANSIColor.red,"alias '#{alias_name}' is calling itself? '#{found_alias_command}'", Term::ANSIColor.reset, "\n"
							exit 1
						end
						# this allows aliases to use other aliases
						# todo: prevent recursion infinite loop
						if has_alias?(command_name) 
							exec_alias(command_name, command_args)
						elsif has_command?(command_name)
							#puts "executing alias #{found_alias_command} as #{command_name} with args #{args.join(' ')}"
							instance.get(command_name).new.handle(alias_args + args)
						else
							# raise UnrecognizedCommandError.new(command_name)
							print Term::ANSIColor.red,"alias '#{alias_name}' uses and unknown command: '#{command_name}'", Term::ANSIColor.reset, "\n"
							exit 1
						end
					end
									end

				def add(klass, command_name=nil)
					klass_command_name = cli_ize(klass.name.split('::')[-1])
					if has_command?(klass_command_name)
						instance.remove(klass_command_name)
					end
					command_name ||= klass_command_name
					instance.add(command_name, klass)
				end

				def has_command?(command_name)
					if command_name.nil? || command_name == ''
						false
					else
						!instance.get(command_name).nil?
					end
				end

				def has_alias?(alias_name)
					if alias_name.nil? || alias_name == ''
						false
					else
						!instance.get_alias(alias_name).nil?
					end
				end

				def all
					instance.all
				end

				def all_aliases
					instance.all_aliases
				end

				def cli_ize(klass_name)
					# borrowed from ActiveSupport
					return klass_name unless klass_name =~ /[A-Z-]|::/
					word = klass_name.to_s.gsub(/::/, '/')
					word.gsub!(/(?:(?<=([A-Za-z\d]))|\b)(?=\b|[^a-z])/) { "#{$1 && '_'}" }
					word.gsub!(/([A-Z\d]+)([A-Z][a-z])/,'\1_\2')
					word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
					word.tr!("-", "_")
					word.downcase!
					word.chop.tr('_', '-')
				end

				def parse_alias_definition(input)
					# todo: one multi group regex would work
					alias_name, command_string = nil, nil
					chunks = input.to_s.sub(/^alias\s+/, "").split('=')
					alias_name = chunks.shift
					command_string = chunks.compact.reject {|it| it.empty? }.join('=')
					command_string = command_string.strip.sub(/^'/, "").sub(/'\Z/, "").strip
					return alias_name, command_string
				end


			end

			def all
				@commands.reject {|cmd, klass| klass.hidden_command }
			end

			def get(cmd_name)
				@commands[cmd_name.to_sym]
			end

			def add(cmd_name, klass)
				@commands[cmd_name.to_sym] = klass
			end

			def remove(cmd_name)
				@commands.delete(cmd_name.to_sym)
			end

			def all_aliases
				@aliases
			end

			def get_alias(alias_name)
				@aliases[alias_name.to_sym]
			end

			def add_alias(alias_name, command_string)
				@aliases[alias_name.to_sym] = command_string
			end

			def remove_alias(alias_name)
				@aliases.delete(alias_name.to_sym)
			end

		end
	end
end
