require 'morpheus/cli/cli_registry'

module Morpheus
  module Cli
    # Module to be included by every CLI command so that commands get registered
    module CliCommand

      def self.included(klass)
        Morpheus::Cli::CliRegistry.add(klass)
        klass.extend ClassMethods
      end

      def self.genericOptions(opts,options)
            opts.on( '-O', '--option OPTION', "Option" ) do |option|
              custom_option_args = option.split('=')
              custom_options = options[:options] || {}
              custom_options[custom_option_args[0]] = custom_option_args[1]
              options[:options] = custom_options
            end
            opts.on('-h','--help', "Help") do |json|
              options[:help] = true
            end
            opts.on('','--json',"JSON") do |json|
              options[:json] = true
            end
            opts.on( '-m', '--max MAX', "Max Results" ) do |max|
              options[:max] = max.to_i
            end

            opts.on( '-o', '--offset OFFSET', "Offset Results" ) do |offset|
              options[:offset] = offset.to_i
            end

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

            opts.on( '-r', '--remote REMOTE', "Remote Appliance" ) do |remote|
              options[:remote] = remote
            end

            opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
              options[:phrase] = phrase
            end
      end



      module ClassMethods
        def cli_command_name(cmd_name)
          Morpheus::Cli::CliRegistry.add(self, cmd_name)
        end

        
      end
    end
  end
end
