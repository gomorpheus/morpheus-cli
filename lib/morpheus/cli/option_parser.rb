require 'optparse'

module Morpheus
  module Cli

    # an enhanced OptionParser
    # not used yet, maybe ever =o
    class Morpheus::Cli::OptionParser < OptionParser

      attr_reader :footer
      
      def footer=(msg)
        @footer = msg
      end

      alias :original_to_s :to_s

      def to_s
        full_help_message
      end

      def full_help_message
        out = ""
        out << original_to_s
        if footer
          out << footer.to_s.strip
          out << "\n"
        end
        out
      end

    end

  end
end
