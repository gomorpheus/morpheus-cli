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

            opts.on( '-r', '--remote REMOTE', "Remote Appliance" ) do |remote|
              options[:remote] = remote
            end

            opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
              options[:phrase] = phrase
            end
      end

      def self.option_types_prompt(option_types, options={})
          results = {}
          options = options || {}
          # puts "Options Prompt #{options}"
          option_types.sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |option_type|
            context_map = results
            value = nil
            value_found=false
            if option_type['fieldContext']
              results[option_type['fieldContext']] ||= {}
              context_map = results[option_type['fieldContext']]
              if options[option_type['fieldContext']] and options[option_type['fieldContext']].key?(option_type['fieldLabel'])
                value = options[option_type['fieldContext']][option_type['fieldLabel']]
                value_found = true
              end
            end

            if value_found == false && options.key?(option_type['fieldName'])
              value = options[option_type['fieldName']]
              value_found = true
            end

            if !value_found
              if option_type['type'] == 'number'
                print "#{option_type['fieldLabel']}#{!option_type['required'] ? ' (optional)' : ''}: "
                input = $stdin.gets.chomp!
                if input
                  value = input.to_i
                else
                  value = option_type['defaultValue']
                end

              elsif option_type['type'] == 'password'
                print "#{option_type['fieldLabel']}#{!option_type['required'] ? ' (optional)' : ''}: "
                value = STDIN.noecho(&:gets).chomp!
                print "\n"
              elsif option_type['type'] == 'checkbox'
                print "#{option_type['fieldLabel']} (yes/no) [#{option_type['defaultValue'] == 'on' ? 'yes' : 'no'}]: "
                input = $stdin.gets.chomp!
                if input.downcase == 'yes'
                  value = 'on'
                elsif input.downcase == 'no'
                  value = 'off'
                else
                  value = option_type['defaultValue']
                end
              elsif option_type['type'] == 'hidden'
                value = option_type['defaultValue']
              else
                print "#{option_type['fieldLabel']}#{!option_type['required'] ? ' (optional)' : ''}: "
                value = $stdin.gets.chomp! || option_type['defaultValue']
              end
            end
            context_map[option_type['fieldName']] = value
          end

          return results
        end

      module ClassMethods
        def cli_command_name(cmd_name)
          Morpheus::Cli::CliRegistry.add(self, cmd_name)
        end

        
      end
    end
  end
end
