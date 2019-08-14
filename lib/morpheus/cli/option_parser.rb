require 'optparse'

module Morpheus
  module Cli

    # an enhanced OptionParser
    # not used yet, maybe ever =o
    class Morpheus::Cli::OptionParser < OptionParser

      attr_accessor :footer

      # Array of option names to keep out of help message
      attr_accessor :hidden_options

      alias :original_to_s :to_s

      def to_s
        full_help_message
      end

      def full_help_message
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
          summarize().each do |opt_description|
            is_hidden = (@hidden_options || []).find { |hidden_switch|
              # opt_description.include?("--#{hidden_switch}")
              if hidden_switch.start_with?("-")
                opt_description.to_s.strip.start_with?("#{hidden_switch} ")
              else
                opt_description.to_s.strip.start_with?("--#{hidden_switch} ")
              end
            }
            if !is_hidden
              out  << opt_description
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

    end

  end
end
