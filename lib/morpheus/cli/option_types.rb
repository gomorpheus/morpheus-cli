require 'term/ansicolor'

module Morpheus
  module Cli
    module OptionTypes
        include Term::ANSIColor


        def self.confirm(message,options={})
          if options[:yes] == true
            return true
          end
          value_found = false
          while value_found == false do
            print "#{message} (yes/no): "
            input = $stdin.gets.chomp!
            if input.downcase == 'yes'
              return true
            elsif input.downcase == 'no'
              return false
            else
              puts "Invalid Option... Please try again."
            end
          end
        end

        def self.prompt(option_types, options={}, api_client=nil,api_params={})
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
                value = number_prompt(option_type)
              elsif option_type['type'] == 'password'
               value = password_prompt(option_type)
              elsif option_type['type'] == 'checkbox'
                value = checkbox_prompt(option_type)
              elsif option_type['type'] == 'radio'
                value = radio_prompt(option_type)
              elsif option_type['type'] == 'textarea'
                value = multiline_prompt(option_type)
              elsif option_type['type'] == 'code-editor'
                value = multiline_prompt(option_type)  
              elsif option_type['type'] == 'select'
                value = select_prompt(option_type,api_client, api_params)
              elsif option_type['type'] == 'hidden'
                value = option_type['defaultValue']
                input = value
              else
                value = generic_prompt(option_type)
              end
              
            end
            context_map[option_type['fieldName']] = value
          end

          return results
        end

        def self.radio_prompt(option_type)
            value_found = false
            value = nil
            options = []
            if option_type['config'] and option_type['config']['radioOptions']
                option_type['config']['radioOptions'].each do |radio_option|
                    options << {key: radio_option['key'], checked: radio_option['checked']}
                end
            end
            optionString = options.collect{ |b| b[:checked] ? "(#{b[:key]})" : b[:key]}.join(', ')
            while !value_found do
                print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }[#{optionString}]: "
                input = $stdin.gets.chomp!
                if input == '?'
                    help_prompt(option_type)
                else
                    if input.nil? || input.empty?
                        selectedOption = options.find{|o| o[:checked] == true}
                    else
                        selectedOption = options.find{|o| o[:key].downcase == input.downcase}   
                    end
                    
                    if selectedOption
                        value = selectedOption[:key]
                    else
                        puts "Invalid Option. Please select from #{optionString}."
                    end
                    if !value.nil? || option_type['required'] != true
                      value_found = true
                    end
                end
            end
            return value
        end

        def self.number_prompt(option_type)
            value_found = false
            value = nil
            while !value_found do
                print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}: "
                input = $stdin.gets.chomp!
                value = input.empty? ? option_type['defaultValue'] : input.to_i
                if input == '?'
                    help_prompt(option_type)
                elsif !value.nil? || option_type['required'] != true
                  value_found = true
                end
            end
            return value
        end

        def self.select_prompt(option_type,api_client, api_params={})
          value_found = false
          value = nil
          if option_type['optionSource']
            source_options = load_source_options(option_type['optionSource'],api_client,api_params)
          end
          while !value_found do
              print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''} ['?' for options]: "
              input = $stdin.gets.chomp!
              if option_type['optionSource']
                source_option = source_options.find{|b| b['name'] == input || b['value'].to_s == input}
                if source_option
                  value = source_option['value']
                elsif !input.nil?  && !input.empty?
                  input = '?'
                end
              else
                value = input.empty? ? option_type['defaultValue'] : input
              end
              
              if input == '?'
                  help_prompt(option_type)
                  display_select_options(source_options)
              elsif !value.nil? || option_type['required'] != true
                value_found = true
              end
          end
          return value
        end

        def self.checkbox_prompt(option_type)
            value_found = false
            value = nil
            while !value_found do
                print "#{option_type['fieldLabel']} (yes/no) [#{option_type['defaultValue'] == 'on' ? 'yes' : 'no'}]: "
                input = $stdin.gets.chomp!
                if input.downcase == 'yes'
                  value = 'on'
                elsif input.downcase == 'no'
                  value = 'off'
                else
                  value = option_type['defaultValue']
                end
                if input == '?'
                    help_prompt(option_type)
                elsif !value.nil? || option_type['required'] != true
                  value_found = true
                end
            end
            return value
        end

        def self.generic_prompt(option_type)
            value_found = false
            value = nil
            while !value_found do
                print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}: "
                input = $stdin.gets.chomp!
                value = input.empty? ? option_type['defaultValue'] : input
                if input == '?'
                    help_prompt(option_type)
                elsif !value.nil? || option_type['required'] != true
                  value_found = true
                end
            end
            return value
        end

        def self.multiline_prompt(option_type)
            value_found = false
            value = nil
            while !value_found do
                if value.nil?
                  print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''} [Type 'EOF' to stop input]: \n"
                end
                input = $stdin.gets.chomp!
                # value = input.empty? ? option_type['defaultValue'] : input
                if input == '?' && value.nil?
                    help_prompt(option_type)
                elsif (!value.nil? || option_type['required'] != true) && input.chomp == 'EOF'
                  value_found = true
                else
                  if value.nil?
                    value = ''
                  end
                  value << input + "\n"
                end
            end
            return value
        end

        def self.password_prompt(option_type)
            value_found = false
            while !value_found do
                print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}: "
                input = STDIN.noecho(&:gets).chomp!
                value = input
                print "\n"
                if input == '?'
                    help_prompt(option_type)
                elsif !value.nil? || option_type['required'] != true
                  value_found = true
                end
            end
            return value
        end

        def self.help_prompt(option_type)
            print Term::ANSIColor.green,"  * #{option_type['fieldLabel']} [-O #{option_type['fieldName']}=] - ", Term::ANSIColor.reset , "#{option_type['description']}\n"
        end


        def self.load_source_options(source,api_client,params)
          api_client.options.options_for_source(source,params)['data']
        end

        def self.display_select_options(select_options = [])
          puts "\nOptions"
          puts "==============="
          select_options.each do |option|
            puts " * #{option['name']} [#{option['value']}]"
          end
          puts "\n\n"
        end
    end
  end
end
