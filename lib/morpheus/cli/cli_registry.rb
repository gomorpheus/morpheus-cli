require 'term/ansicolor'
require 'shellwords'
require 'morpheus/logging'
require 'morpheus/cli/errors'
require 'morpheus/cli/error_handler'
require 'morpheus/cli/expression_parser'
require 'morpheus/ext/string'

module Morpheus
  module Cli
    class CliRegistry

      class BadCommandDefinition < StandardError
      end

      class BadAlias < StandardError
      end

      def initialize
        @commands = {} # this is command => Class that includes ::CliCommand
        @aliases = {} # this is alias => String full input string
      end

      def flush
        @commands = {}
        @aliases = {}
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
        #return @commands[alias_name.to_sym]
        if self.class.has_command?(alias_name)
          raise BadAlias.new "alias name '#{alias_name}' is invalid. That is the name of a morpheus command."
        elsif alias_name.to_s.downcase.strip == command_string.to_s.downcase.strip
          raise BadAlias.new "alias #{alias_name}=#{command_string} is invalid..."
        end
        @aliases[alias_name.to_sym] = command_string
      end

      def remove_alias(alias_name)
        @aliases.delete(alias_name.to_sym)
      end

      class << self
        include Term::ANSIColor

        def instance
          @instance ||= CliRegistry.new
        end

        #todo: move execution out of the CliRegistry
        def exec(command_name, args)
          exec_command(command_name, args)
        end

        def exec_command(command_name, args)
          #puts "exec_command(#{command_name}, #{args})"
          result = nil
          if has_alias?(command_name)
            result = exec_alias(command_name, args)
          elsif has_command?(command_name)
            begin
              result = instance.get(command_name).new.handle(args)
            rescue SystemExit => e
              result = Morpheus::Cli::ErrorHandler.new(Morpheus::Terminal.instance.stderr).handle_error(e) # lol
            rescue => e
              result = Morpheus::Cli::ErrorHandler.new(Morpheus::Terminal.instance.stderr).handle_error(e) # lol
            end
          else
            # todo: need to just return error instead of raise
            msg = "'#{command_name}' is not a morpheus command."
            suggestions = find_command_suggestions(command_name)
            if suggestions && suggestions.size == 1
              msg += "\nThe most similar command is:\n"
              msg += "\t" + suggestions.first + "\n"
            elsif suggestions && suggestions.size > 1
              msg += "\nThe most similar commands are:\n"
              suggestions.first(50).each do |suggestion|
                msg += "\t" + suggestion + "\n"
              end
            end
            #raise CommandNotFoundError.new(msg)
            result = Morpheus::Cli::ErrorHandler.new(Morpheus::Terminal.instance.stderr).handle_error(CommandNotFoundError.new(msg)) # lol
          end
          return result
        end

        def exec_alias(alias_name, args)
          found_alias_command = instance.get_alias(alias_name)
          if !found_alias_command
            raise Morpheus::Cli::CommandError.new("'#{alias_name}' is not a defined alias.")
          end
          # if !is_valid_expression(found_alias_command)
          #   raise Morpheus::Cli::CommandError.new("alias '#{alias_name}' is not a valid expression: #{found_alias_command}")
          # end
          input = found_alias_command
          if args && !args.empty?
            input = "#{found_alias_command} " + args.collect {|arg| arg.include?(" ") ? "\"#{arg}\"" : "#{arg}" }.join(" ")
          end
          exec_expression(input)
        end

        def exec_expression(input)
          # puts "exec_expression(#{input})"
          flow = input
          if input.is_a?(String)
            begin
              flow = Morpheus::Cli::ExpressionParser.parse(input)
            rescue Morpheus::Cli::ExpressionParser::InvalidExpression => e
              raise e
            end
          end
          # puts "executing flow: #{flow.inspect}"
          final_command_result = nil
          if flow.size == 0
            # no input eh?
          else
            last_command_result = nil
            if ['&&','||', '|'].include?(flow.first)
              raise Morpheus::Cli::ExpressionParser::InvalidExpression.new "#{Morpheus::Terminal.angry_prompt}invalid command format, begins with an operator: #{input}"
            elsif ['&&','||', '|'].include?(flow.last)
              raise Morpheus::Cli::ExpressionParser::InvalidExpression.new "#{Morpheus::Terminal.angry_prompt}invalid command format, ends with an operator: #{input}"
            # elsif ['&&','||', '|'].include?(flow.last)
            #   raise Morpheus::Cli::ExpressionParser::InvalidExpression.new "invalid command format, consecutive operators: #{cmd}"
            else
              #Morpheus::Logging::DarkPrinter.puts "Executing command flow: #{flow.inspect}" if Morpheus::Logging.debug?
              previous_command = nil
              previous_command_result = nil
              current_operator = nil
              still_executing = true
              # need to error before executing anything, could be dangerous otherwise!
              # also maybe only pass flow commands if they have a space on either side..
              if flow.include?("|")
                raise Morpheus::Cli::ExpressionParser::InvalidExpression.new "The PIPE (|) operator is not yet supported. You can wrap your arguments in quotations."
              end
              flow.each do |flow_cmd|
                if still_executing
                  if flow_cmd == '&&'
                    # AND operator
                    current_operator = flow_cmd
                    exit_code, cmd_err = parse_command_result(previous_command_result)
                    if exit_code != 0
                      still_executing = false
                    end
                  elsif flow_cmd == '||' # or with previous command
                    current_operator = flow_cmd
                    exit_code, err = parse_command_result(previous_command_result)
                    if exit_code == 0
                      still_executing = false
                    end
                  elsif flow_cmd == '|' # or with previous command
                    # todo, handle pipe!
                    raise Morpheus::Cli::ExpressionParser::InvalidExpression.new "The PIPE (|) operator is not yet supported. You can wrap your arguments in quotations."
                    previous_command_result = nil
                    still_executing = false
                    # or just continue?
                  elsif flow_cmd.is_a?(Array)
                    # this is a subexpression, execute it as such
                    current_operator = nil
                    previous_command_result = exec_expression(flow_cmd)
                  else # it's a command, not an operator
                    current_operator = nil
                    flow_argv = Shellwords.shellsplit(flow_cmd)
                    previous_command_result = exec_command(flow_argv[0], flow_argv[1..-1])
                  end
                  previous_command = flow_cmd
                else
                  #Morpheus::Logging::DarkPrinter.puts "operator skipped command: #{flow_cmd}" if Morpheus::Logging.debug?
                end
                # previous_command = flow_cmd
              end
              final_command_result = previous_command_result
            end
          end
          return final_command_result
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

        # parse any object into a command result [exit_code, error]
        # 0 means success.
        # This treats nil, true, or an object as success ie. [0, nil]
        # and false is treated as an error [1, error]
        # @return [Array] [exit_code, error]. Success returns [0, nil].
        def parse_command_result(cmd_result)
          exit_code, error = nil, nil
          if cmd_result.is_a?(Array)
            exit_code = cmd_result[0] || 0
            error = cmd_result[1]
          elsif cmd_result.is_a?(Hash)
            exit_code = cmd_result[:exit_code] || 0
            error = cmd_result[:error] || cmd_result[:err]
          elsif cmd_result == nil || cmd_result == true
            exit_code = 0
          elsif cmd_result == false
            exit_code = 1
          elsif cmd_result.is_a?(Integer)
            exit_code = cmd_result
          elsif cmd_result.is_a?(Float)
            exit_code = cmd_result.to_i
          elsif cmd_result.is_a?(String)
            exit_code = cmd_result.to_i
          else
            if cmd_result.respond_to?(:to_i)
              exit_code = cmd_result.to_i
            else
              # happens for aliases right now.. and execution flow probably, need to handle Array
              # uncomment to track them down, proceed with exit 0 for now
              #Morpheus::Logging::DarkPrinter.puts "debug: command #{command_name} produced an unexpected result: (#{cmd_result.class}) #{cmd_result}" if Morpheus::Logging.debug?
              exit_code = 0
            end
          end
          return exit_code, error
        end

        def cached_command_list
          @cached_command_list ||= (all.keys + all_aliases.keys).collect { |it| it.to_s }.sort
        end

        def clear_cached_command_list
          @cached_command_list = nil
        end

        # find suggested commands (or aliases) for a name that was not found
        # First this looks for the plural of the original guess
        # Then pop characters off the end looking for partial matches
        # as long as the guess is at least 3 characters
        def find_command_suggestions(command_name)
          every_command = cached_command_list
          guess = command_name
          suggestions = []
          while suggestions.empty? && guess.size >= 3
            plural_guess = guess.pluralize
            if every_command.include?(guess)
              suggestions << guess
            end
            if every_command.include?(plural_guess)
              suggestions << plural_guess
            end
            # if every_command.include?(guess)
            #   suggestions << plural_guess
            # else
              guess_regexp = /^#{Regexp.escape(guess)}/i
              every_command.each do |it|
                if it =~ guess_regexp
                  suggestions << it
                end
              end
            # end
            guess = guess[0..-2]
          end
          suggestions.uniq!
          suggestions.sort! { |x,y| [x.split('-').size, x] <=> [y.split('-').size, y] }
          return suggestions
        end

      end

    end
  end
end
