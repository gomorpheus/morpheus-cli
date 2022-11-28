require 'optparse'

module Morpheus
  module Cli

    # an enhanced OptionParser
    # Modifications include
    # * footer property to compliment banner with footer="Get details about a thing by ID."
    # * hidden options with add_hidden_option "--not-in-help"
    # * errors raised from parse! will have a reference to the parser itself.
    #    this is useful so you can you print the banner (usage) message in your error handling
    class Morpheus::Cli::OptionParser < OptionParser

      attr_accessor :footer

      # Array of option names to keep out of help message
      attr_accessor :hidden_options

      alias :original_to_s :to_s

      def to_s
        full_help_message
      end

      def full_help_message(opts={})
        out = ""
        #out << original_to_s
        if banner
          out << "#{banner}".sub(/\n?\z/, "\n")
        end
        if !self.to_a.empty?
          #out << "Options:\n"
          # the default way..
          # out << summarize().join("")
          # super hacky, should be examining the option, not the fully formatted description
          my_summaries = summarize()
          if opts[:show_hidden_options]
            my_summaries.each do |full_line|
              out << full_line
            end
          else
            on_hidden_option = false
            my_summaries.each do |full_line|
              opt_description = full_line.to_s.strip
              if opt_description.start_with?("-")
                is_hidden = (hidden_options || []).find { |hidden_switch|
                  if hidden_switch.start_with?("-")
                    opt_description.start_with?("#{hidden_switch} ")
                  else
                    opt_description.start_with?("--#{hidden_switch} ")
                  end
                }
                if is_hidden
                  on_hidden_option = true
                else
                  on_hidden_option = false
                  out << full_line
                end
              else
                if on_hidden_option == false
                  out << full_line
                end
              end
            end
          end
        end
        if footer
          # nice_footer = footer.split("\n").collect {|line| "#{summary_indent}#{line}" }.join("\n")
          nice_footer = footer
          out << "\n"
          out << "#{nice_footer}".sub(/\n?\z/, "\n")
          # out << "\n"
        end
        out
      end

      def hidden_options
        @hidden_options ||= []
      end

      def add_hidden_option(opt_name)
        opt_array = [opt_name].flatten.compact
        @hidden_options ||= []
        opt_array.each do |val|
          if !@hidden_options.include?(val)
            @hidden_options << val
          end
        end
        @hidden_options
      end

      # this needs mods too, but we dont use it...
      # def parse
      # end

      def parse!(*args)
        # it is actually # def parse(argv = default_argv, into: nil)
        argv = [args].flatten() # args[0].flatten
        #help_wanted = argv.find {|arg| arg == "--help" || arg ==  "-h" }
        help_wanted = (argv.last == "--help" || argv.last ==  "-h") ? argv.last : nil
        begin
          return super(*args)
        rescue OptionParser::ParseError => e
          # last arg is --help
          # maybe they just got the Try --help message and its on the end
          # so strip all option arguments to avoid OptionParser::InvalidOption, etc.
          # this is not ideal, it means you cannot pass these strings as the last argument to your command.
          if help_wanted
            argv = argv.reject {|arg| arg =~ /^\-+/ }
            argv << help_wanted
            return super(argv)
          else
            e.optparse = self
            raise e
          end
          
        end
      end
    end
  end
end

# ParseError is overridden to set parser reference.
# todo: dont monkey patch like this
class OptionParser::ParseError
  attr_accessor :optparse
end
