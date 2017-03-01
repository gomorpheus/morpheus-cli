require 'optparse'

module Morpheus
  module Cli

    # an enhanced OptionParser
    # not used yet, maybe ever =o
    class Morpheus::Cli::OptionParser < OptionParser

      attr_accessor :footer
      
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
          out << summarize().join("")
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

    end

  end
end
