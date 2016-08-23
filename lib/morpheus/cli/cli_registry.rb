
module Morpheus
  module Cli
    class CliRegistry

      def initialize
        @commands = {}
      end
      
      class << self
        
        def instance
          @instance ||= CliRegistry.new
        end

        def exec(command_name, args)
          begin
            instance.get(command_name).new.handle(args)
          rescue SystemExit, Interrupt
            puts "Interrupted..."
          end
        end

        def add(klass, command_name=nil)
          klass_command_name = cli_ize(klass.name.split('::')[-1])

          if has_command?(klass_command_name) && !command_name.nil?
            instance.remove(klass_command_name)
            instance.add(command_name, klass)
          else
            instance.add(klass_command_name, klass)
          end
        end

        def has_command?(command_name)
          if command_name.nil? || command_name == ''
            false
          else
            !instance.get(command_name).nil?
          end
        end

        def all
          instance.all
        end

        private

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
      end

      def all
        @commands
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
    end
  end
end
