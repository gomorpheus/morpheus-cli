require 'term/ansicolor'
require 'readline'
require 'csv'
module Morpheus
  module Cli
    module OptionTypes
      include Term::ANSIColor
      # include Morpheus::Cli::PrintHelper

      def self.confirm(message,options={})
        if options[:yes] == true
          return true
        end
        default_value = options[:default]
        value_found = false
        while value_found == false do
          if default_value.nil?
            print "#{message} (yes/no): "
          else
            print "#{message} (yes/no) [#{!!default_value ? 'yes' : 'no'}]: "
          end
          input = $stdin.gets.chomp!
          if input.empty? && !default_value.nil?
            return !!default_value
          end
          if input.downcase == 'yes' || input.downcase == 'y'
            return true
          elsif input.downcase == 'no' || input.downcase == 'n'
            return false
          else
            puts "Invalid Option... Please try again."
          end
        end
      end

      # supresses prompting unless --prompt has been passed
      def self.no_prompt(option_types, options={}, api_client=nil,api_params={})
        if options[:always_prompt]
          prompt(option_types, options, api_client, api_params)
        else
          prompt(option_types, options, api_client, api_params, true)
        end
      end

      def self.prompt(option_types, options={}, api_client=nil, api_params={}, no_prompt=false, paging_enabled=false)
        paging_enabled = false if Morpheus::Cli.windows?
        no_prompt = no_prompt || options[:no_prompt]
        results = {}
        options = options || {}

        # inject cli only stuff into option_types (should clone() here)
        option_types.each do |option_type|
          if options[:help_field_prefix]
            option_type[:help_field_prefix] = options[:help_field_prefix]
          end
          # a lot of optionTypes have fieldGroup:'Options' instead of 'default'
          if option_type['fieldGroup'].to_s.downcase == 'options'
            option_type['fieldGroup'] = 'default'
          end
        end
        # puts "Options Prompt #{options}"
        # Sort options by default, group, advanced
        cur_field_group = 'default'
        self.sorted_option_types(option_types).each do |option_type|
          context_map = results
          value = nil
          value_found = false
          field_group = (option_type['fieldGroup'] || 'default').to_s.sub(/options\Z/i, "").strip # avoid "ADVANCED OPTION OPTIONS"

          if cur_field_group != field_group
            cur_field_group = field_group
            if !no_prompt 
              print "\n#{cur_field_group.upcase} OPTIONS\n#{"=" * ("#{cur_field_group} OPTIONS".length)}\n\n"
            end
          end

          # How about this instead?
          # option_type = option_type.clone
          # field_key = [option_type['fieldContext'], option_type['fieldName']].select {|it| it && it != '' }.join('.')
          # if field_key != ''
          #   value = get_object_value(options, field_key)
          #   if value != nil && options[:always_prompt] != true
          #     value_found = true
          #   end
          # end

          # allow for mapping of domain to relevant type: domain.zone => router.zone
          option_type['fieldContext'] = (options[:context_map] || {})[option_type['fieldContext']] || option_type['fieldContext']
          field_key = [option_type['fieldContext'], option_type['fieldName']].select {|it| it && it != '' }.join('.')
          help_field_key = option_type[:help_field_prefix] ? "#{option_type[:help_field_prefix]}.#{field_key}" : field_key
          namespaces = field_key.split(".")
          field_name = namespaces.pop

          # respect optionType.dependsOnCode
          # i guess this switched to visibleOnCode, respect one or the other
          visible_option_check_value = option_type['dependsOnCode']
          if !option_type['visibleOnCode'].to_s.empty?
            visible_option_check_value = option_type['visibleOnCode']
          end

          if !visible_option_check_value.to_s.empty?
            match_type = 'any'

            if visible_option_check_value.include?('::')
              match_type = 'all' if visible_option_check_value.start_with?('matchAll')
              visible_option_check_value = visible_option_check_value[visible_option_check_value.index('::') + 2..-1]
            end

            found_dep_value = match_type == 'all' ? true : false
            visible_option_check_value.sub(',', ' ').split(' ').each do |value|
              parts = value.split(':')
              depends_on_code = parts[0]
              depends_on_value = parts.count > 1 ? parts[1].to_s.strip : nil
              depends_on_option_type = option_types.find {|it| it["code"] == depends_on_code }
              if !depends_on_option_type
                depends_on_option_type = option_types.find {|it|
                  (it['fieldContext'] ? "#{it['fieldContext']}.#{it['fieldName']}" : it['fieldName']) == depends_on_code
                }
              end

              if depends_on_option_type
                depends_on_field_key = depends_on_option_type['fieldContext'].nil? || depends_on_option_type['fieldContext'].empty? ? "#{depends_on_option_type['fieldName']}" : "#{depends_on_option_type['fieldContext']}.#{depends_on_option_type['fieldName']}"
              else
                depends_on_field_key = depends_on_code
              end

              field_value = get_object_value(results, depends_on_field_key) ||
                            get_object_value(options, depends_on_field_key) ||
                            get_object_value(api_params, depends_on_field_key)

              if !field_value.nil? && (depends_on_value.nil? || depends_on_value.empty? || field_value.match?(depends_on_value))
                found_dep_value = true if match_type != 'all'
              else
                found_dep_value = false if match_type == 'all'
              end
            end
            next if !found_dep_value
          end

          cur_namespace = options
          parent_context_map = context_map
          parent_ns = field_name

          namespaces.each do |ns|
            next if ns.empty?
            parent_context_map = context_map
            parent_ns = ns
            cur_namespace[ns.to_s] ||= {}
            cur_namespace = cur_namespace[ns.to_s]
            context_map[ns.to_s] ||= {}
            context_map = context_map[ns.to_s]
          end

          # build parameters for option source api request
          option_params = (option_type['noParams'] ? {} : (api_params || {}).merge(results))
          option_params.merge!(option_type['optionParams']) if option_type['optionParams']

          # use the value passed in the options map
          if cur_namespace.respond_to?('key?') && cur_namespace.key?(field_name)
            value = cur_namespace[field_name]
            input_value = ['select', 'multiSelect','typeahead', 'multiTypeahead'].include?(option_type['type']) && option_type['fieldInput'] ? cur_namespace[option_type['fieldInput']] : nil
            if option_type['type'] == 'number'
              if !value.to_s.empty?
                value = value.to_s.include?('.') ? value.to_f : value.to_i
              end
            # these select prompts should just fall down through below, with the extra params no_prompt, use_value
            elsif option_type['type'] == 'select'
              value = select_prompt(option_type.merge({'defaultValue' => value, 'defaultInputValue' => input_value}), api_client, option_params, true)
            elsif option_type['type'] == 'multiSelect'
              # support value as csv like "thing1, thing2"
              value_list = value.is_a?(String) ? value.parse_csv.collect {|v| v ? v.to_s.strip : v } : [value].flatten
              input_value_list = input_value.is_a?(String) ? input_value.parse_csv.collect {|v| v ? v.to_s.strip : v } : [input_value].flatten
              select_value_list = []
              value_list.each_with_index do |v, i|
                select_value_list << select_prompt(option_type.merge({'defaultValue' => v, 'defaultInputValue' => input_value_list[i]}), api_client, option_params, true)
              end
              value = select_value_list
            elsif option_type['type'] == 'typeahead'
              value = typeahead_prompt(option_type.merge({'defaultValue' => value, 'defaultInputValue' => input_value}), api_client, option_params, true)
            elsif option_type['type'] == 'multiTypeahead'
              # support value as csv like "thing1, thing2"
              value_list = value.is_a?(String) ? value.parse_csv.collect {|v| v ? v.to_s.strip : v } : [value].flatten
              input_value_list = input_value.is_a?(String) ? input_value.parse_csv.collect {|v| v ? v.to_s.strip : v } : [input_value].flatten
              select_value_list = []
              value_list.each_with_index do |v, i|
                select_value_list << typeahead_prompt(option_type.merge({'defaultValue' => v, 'defaultInputValue' => input_value_list[i]}), api_client, option_params, true)
              end
              value = select_value_list
            end
            if options[:always_prompt] != true
              value_found = true
            end
          end

          # set the value that has been passed to the option type default value
          if value != nil # && value != ''
            option_type = option_type.clone
            option_type['defaultValue'] = value
          end
          # no_prompt means skip prompting and instead
          # use default value or error if a required option is not present
          if no_prompt
            if !value_found
              if option_type['defaultValue'] != nil && !['select', 'multiSelect','typeahead','multiTypeahead'].include?(option_type['type'])
                value = option_type['defaultValue']
                value_found = true
              end
              if !value_found
                # select type is special because it supports skipSingleOption
                # and prints the available options on error
                if ['select', 'multiSelect'].include?(option_type['type'])
                  value = select_prompt(option_type, api_client, option_params, true)
                  value_found = !!value
                end
                if ['typeahead', 'multiTypeahead'].include?(option_type['type'])
                  value = typeahead_prompt(option_type, api_client, option_params, true)
                  value_found = !!value
                end
                if !value_found
                  if option_type['required']
                    print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
                    print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{help_field_key}=] - #{option_type['description']}\n", Term::ANSIColor.reset
                    print "\n"
                    exit 1
                  else
                    next
                  end
                end
              end
            end
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
            elsif ['select', 'multiSelect'].include?(option_type['type'])
              # so, the /api/options/source is may need ALL the previously
              # selected values that are being accumulated in options
              # api_params is just extra params to always send
              # I suppose the entered value should take precedence
              # api_params = api_params.merge(options) # this might be good enough
              # dup it
              value = select_prompt(option_type, api_client, option_params, options[:no_prompt], nil, paging_enabled)
              if value && option_type['type'] == 'multiSelect'
                value = [value]
                while self.confirm("Add another #{option_type['fieldLabel']}?", {:default => false}) do
                  if addn_value = select_prompt(option_type, api_client, option_params, options[:no_prompt], nil, paging_enabled)
                    value << addn_value
                  else
                    break
                  end
                end
              end
            elsif ['typeahead', 'multiTypeahead'].include?(option_type['type'])
              value = typeahead_prompt(option_type, api_client, option_params, options[:no_prompt], nil, paging_enabled)
              if value && option_type['type'] == 'multiTypeahead'
                value = [value]
                while self.confirm("Add another #{option_type['fieldLabel']}?", {:default => false}) do
                  if addn_value = typeahead_prompt(option_type, api_client, option_params, options[:no_prompt], nil, paging_enabled)
                    value << addn_value
                  else
                    break
                  end
                end
              end
            elsif option_type['type'] == 'hidden'
              if option_type['optionSource'].nil?
                value = option_type['defaultValue']
              else
                value = load_source_options(option_type['optionSource'], option_params, api_client, api_params || {})
              end
            elsif option_type['type'] == 'file'
              value = file_prompt(option_type)
            elsif option_type['type'] == 'file-content'
              value = file_content_prompt(option_type, options, api_client, {})
            else
              value = generic_prompt(option_type)
            end
          end

          if option_type['type'] == 'multiSelect'
            value = [value] if !value.nil? && !value.is_a?(Array)
            # parent_context_map[parent_ns] = value
          elsif option_type['type'] == 'multiText'
            # multiText expects csv value
            if value && value.is_a?(String)
              value = value.split(",").collect {|it| it.strip }
            end
          end
          context_map[field_name] = value if !(value.nil? || (value.is_a?(Hash) && value.empty?))
          parent_context_map.reject! {|k,v| k == parent_ns && (v.nil? || (v.is_a?(Hash) && v.empty?))}
        end
        results
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
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }[#{optionString}]: "
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
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          input = $stdin.gets.chomp!
          value = input.empty? ? option_type['defaultValue'] : input
          if !value.to_s.empty?
            value = value.to_s.include?('.') ? value.to_f : value.to_i
          end
          if input == '?'
            help_prompt(option_type)
          elsif !value.nil? || option_type['required'] != true
            value_found = true
          end
        end
        return value
      end


      def self.set_last_select(obj)
        Thread.current[:_last_select] = obj
      end

      def self.get_last_select()
        Thread.current[:_last_select]
      end

      def self.select_prompt(option_type,api_client, api_params={}, no_prompt=false, use_value=nil, paging_enabled=false)
        paging_enabled = false if Morpheus::Cli.windows?
        field_key = [option_type['fieldContext'], option_type['fieldName']].select {|it| it && it != '' }.join('.')
        help_field_key = option_type[:help_field_prefix] ? "#{option_type[:help_field_prefix]}.#{field_key}" : field_key
        value_found = false
        value = nil
        value_field = (option_type['config'] ? option_type['config']['valueField'] : nil) || 'value'
        default_value = option_type['defaultValue']
        default_value = default_value['id'] if default_value && default_value.is_a?(Hash) && !default_value['id'].nil?

        if !option_type['params'].nil?
          api_params = (api_params || {}).select {|k,v| option_type['params'].key?(k) || option_type['params'].key?(k.to_s)}
          option_type['params'].select {|k,v| !v.empty?}.each {|k,v| api_params[k] = v}
        end

        # local array of options
        if option_type['selectOptions']
          # calculate from inline lambda
          if option_type['selectOptions'].is_a?(Proc)
            select_options = option_type['selectOptions'].call(api_client, api_params || {})
          else
            # todo: better type validation
            select_options = option_type['selectOptions']
          end
        elsif option_type['optionSource']
          # calculate from inline lambda
          if option_type['optionSource'].is_a?(Proc)
            select_options = option_type['optionSource'].call(api_client, api_params || {})
          elsif option_type['optionSource'] == 'list'
            # /api/options/list is a special action for custom OptionTypeLists, just need to pass the optionTypeId parameter
            select_options = load_source_options(option_type['optionSource'], option_type['optionSourceType'], api_client, api_params || {}.merge({'optionTypeId' => option_type['id']}))
          else
            # remote optionSource aka /api/options/$optionSource?
            select_options = load_source_options(option_type['optionSource'], option_type['optionSourceType'], api_client, api_params || {})
          end
        else
          raise "option '#{field_key}' is type: 'select' and missing selectOptions or optionSource!"
        end

        # ensure the preselected value (passed as an option) is in the dropdown
        if !use_value.nil?
          matched_option = select_options.find {|opt| opt[value_field].to_s == use_value.to_s || opt['name'].to_s == use_value.to_s }
          if !matched_option.nil?
            value = matched_option[value_field]
            value_found = true
          else
            print Term::ANSIColor.red, "\nInvalid Option #{option_type['fieldLabel']}: [#{use_value}]\n\n", Term::ANSIColor.reset
            print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{option_type['fieldContext'] ? (option_type['fieldContext']+'.') : ''}#{option_type['fieldName']}=] - #{option_type['description']}\n", Term::ANSIColor.reset
            if select_options && select_options.size > 10
              display_select_options(option_type, select_options.first(10))
              puts " (#{select_options.size-10} more)"
            else
              display_select_options(option_type, select_options)
            end
            print "\n"
            exit 1
          end
        # skipSingleOption is no longer supported
        # elsif !select_options.nil? && select_options.count == 1 && option_type['skipSingleOption'] == true
        #   value_found = true
        #   value = select_options[0]['value']
        # if there is just one option, use it as the defaultValue
        elsif !select_options.nil? && select_options.count == 1
          if option_type['required'] && default_value.nil?
            default_value = select_options[0]['name'] # name is prettier than value
          end
        elsif !select_options.nil?
          if default_value.nil?
            found_default_option = select_options.find {|opt| opt['isDefault'] == true }
            if found_default_option
              default_value = found_default_option['name'] # name is prettier than value
            end
          else
            found_default_option = select_options.find {|opt| opt[value_field].to_s == default_value.to_s || opt['name'] == default_value.to_s}
            found_default_option = select_options.find {|opt| opt[value_field].to_s.start_with?(default_value.to_s) || opt['name'].to_s.start_with?(default_value.to_s)} if !found_default_option
            if found_default_option
              default_value = found_default_option['name'] # name is prettier than value
            end
          end
        end

        if no_prompt
          if !value_found
            if !default_value.nil? && !select_options.nil? && select_options.find {|it| it['name'] == default_value || it[value_field].to_s == default_value.to_s}
              value_found = true
              value = select_options.find {|it| it['name'] == default_value || it[value_field].to_s == default_value.to_s}[value_field]
            elsif !select_options.nil? && select_options.count > 1 && option_type['autoPickOption'] == true
              value_found = true
              value = select_options[0][value_field]
            elsif option_type['required']
              print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
              print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{help_field_key}=] - #{option_type['description']}\n", Term::ANSIColor.reset
              if select_options && select_options.size > 10
                display_select_options(option_type, select_options.first(10))
                puts " (#{select_options.size-10} more)"
              else
                display_select_options(option_type, select_options)
              end
              print "\n"
              exit 1
            else
              return nil
            end
          end
        end

        paging = nil
        if paging_enabled
          option_count = select_options ? select_options.count : 0
          page_size = Readline.get_screen_size[0] - 6
          if page_size < option_count
            paging = {:cur_page => 0, :page_size => page_size, :total => option_count}
          end
        end

        while !value_found do
          Readline.completion_append_character = ""
          Readline.basic_word_break_characters = ''
          Readline.completion_proc = proc {|s| 
            matches = []
            available_options = (select_options || [])
            available_options.each{|option| 
              if option['name'] && option['name'] =~ /^#{Regexp.escape(s)}/
                matches << option['name']
              # elsif option['id'] && option['id'].to_s =~ /^#{Regexp.escape(s)}/
              elsif option[value_field] && option[value_field].to_s == s
                matches << option['name']
              end
            }
            matches
          }

          has_more_pages = paging && (paging[:cur_page] * paging[:page_size]) < paging[:total]
          input = Readline.readline("#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!default_value.to_s.empty? ? ' ['+default_value.to_s+']' : ''} ['?' for#{has_more_pages && paging[:cur_page] > 0 ? ' more ' : ' '}options]: ", false).to_s
          input = input.chomp.strip
          if input.empty? && default_value
            input = default_value.to_s
          end
          select_option = select_options.find{|b| b['name'] == input || (!b['value'].nil? && b['value'].to_s == input) || (!b[value_field].nil? && b[value_field].to_s == input) || (b[value_field].nil? && input.empty?)}
          if select_option
            value = select_option[value_field]
            set_last_select(select_option)
          elsif !input.nil?  && !input.to_s.empty?
            input = '?'
          end
          
          if input == '?'
            help_prompt(option_type)
            display_select_options(option_type, select_options, paging)
            if paging
              paging[:cur_page] = (paging[:cur_page] + 1) * paging[:page_size] < paging[:total] ? paging[:cur_page] + 1 : 0
            end
          elsif !value.nil? || option_type['required'] != true
            value_found = true
          end
        end

        # wrap in object when using fieldInput
        if value && !option_type['fieldInput'].nil?
          value = {option_type['fieldName'].split('.').last => value, option_type['fieldInput'] => (no_prompt ? option_type['defaultInputValue'] : field_input_prompt(option_type))}
        end
        value
      end

      # this works like select_prompt, but refreshes options with ?query=value between inputs
      # paging_enabled is ignored right now
      def self.typeahead_prompt(option_type,api_client, api_params={}, no_prompt=false, use_value=nil, paging_enabled=false)
        paging_enabled = false if Morpheus::Cli.windows?
        paging = nil
        select_options = nil
        field_key = [option_type['fieldContext'], option_type['fieldName']].select {|it| it && it != '' }.join('.')
        help_field_key = option_type[:help_field_prefix] ? "#{option_type[:help_field_prefix]}.#{field_key}" : field_key
        input = ""
        value_found = false
        value = nil
        value_field = (option_type['config'] ? option_type['config']['valueField'] : nil) || 'value'
        default_value = option_type['defaultValue']
        default_value = default_value['id'] if default_value && default_value.is_a?(Hash) && !default_value['id'].nil?

        while !value_found do
          # ok get input, refresh options and see if it matches
          # if matches one, cool otherwise print matches and reprompt or error
          if use_value
            input = use_value
          elsif no_prompt
            input = default_value
          else
            Readline.completion_append_character = ""
            Readline.basic_word_break_characters = ''
            Readline.completion_proc = proc {|s| 
              matches = []
              available_options = (select_options || [])
              available_options.each{|option| 
                if option['name'] && option['name'] =~ /^#{Regexp.escape(s)}/
                  matches << option['name']
                # elsif option['id'] && option['id'].to_s =~ /^#{Regexp.escape(s)}/
                elsif option[value_field] && option[value_field].to_s == s
                  matches << option['name']
                end
              }
              matches
            }
            # prompt for typeahead input value
            has_more_pages = paging && ((paging[:cur_page] + 1) * paging[:page_size]) < paging[:total]
            input = Readline.readline("#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!default_value.to_s.empty? ? ' ['+default_value.to_s+']' : ''} ['?' for#{has_more_pages ? ' more ' : ' '}options]: ", false).to_s
            input = input.chomp.strip
          end

          # just hit enter, use [default] if set
          if input.empty? && default_value
            input = default_value.to_s
          end
          
          # not required and no value? ok proceed
          if input.to_s == "" && option_type['required'] != true
            value_found = true
            value = nil # or "" # hmm
            #next
            break
          end

          # required and no value? you need help
          # if input.to_s == "" && option_type['required'] == true
          #   help_prompt(option_type)
          #   display_select_options(option_type, select_options) unless select_options.empty?
          #   next
          # end

          # looking for help with this input
          if input == '?'
            help_prompt(option_type)
            select_options = select_options || load_options(option_type, api_client, api_params)

            if !select_options.empty?
              if paging_enabled
                if paging.nil?
                  option_count = select_options ? select_options.count : 0
                  page_size = Readline.get_screen_size[0] - 6
                  if page_size < option_count
                    paging = {:cur_page => 0, :page_size => page_size, :total => option_count}
                  end
                else
                  paging[:cur_page] = (paging[:cur_page] + 1) * paging[:page_size] < paging[:total] ? paging[:cur_page] + 1 : 0
                end
              end
              display_select_options(option_type, select_options, paging)
            end
            next
          end

          # just hit enter? scram
          # looking for help with this input
          # if input == ""
          #   help_prompt(option_type)
          #   display_select_options(option_type, select_options)
          #   next
          # end

          # this is how typeahead works, it keeps refreshing the options with a new ?query={value}
          # query_value = (value || use_value || default_value || '')
          query_value = (input || '')
          api_params ||= {}
          api_params['query'] = query_value
          # skip refresh if you just hit enter
          if !query_value.empty?
            select_options = load_options(option_type, api_client, api_params, query_value)
          end

          # match input to option name or value
          # actually that is redundant, it should already be filtered to matches
          # and can just do this:
          # select_option = select_options.size == 1 ? select_options[0] : nil
          select_option = select_options.find{|b| (b[value_field] && (b[value_field].to_s == input.to_s)) || ((b[value_field].nil? || b[value_field] == "") && (input == "")) }
          if select_option.nil?
            select_option = select_options.find{|b| b['name'] && b['name'] == input }
          end

          # found matching value, else did not find a value, show matching options and prompt again or error
          if select_option
            value = select_option[value_field]
            set_last_select(select_option)
            value_found = true
          else
            if use_value || no_prompt
              # todo: make this nicer
              # help_prompt(option_type)
              print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
              print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{help_field_key}=] - #{option_type['description']}\n", Term::ANSIColor.reset
              if select_options && select_options.size > 10
                display_select_options(option_type, select_options.first(10))
                puts " (#{select_options.size-10} more)"
              else
                display_select_options(option_type, select_options)
              end
              print "\n"
              if select_options.empty?
                print "The value '#{input}' matched 0 options.\n"
                # print "Please try again.\n"
              else
                print "The value '#{input}' matched #{select_options.size()} options.\n"
                print "Perhaps you meant one of these? #{ored_list(select_options.collect {|i|i['name']}, 3)}\n"
                # print "Please try again.\n"
              end
              print "\n"
              exit 1
            else
              #help_prompt(option_type)
              display_select_options(option_type, select_options)
              print "\n"
              if select_options.empty?
                print "The value '#{input}' matched 0 options.\n"
                print "Please try again.\n"
              else
                print "The value '#{input}' matched #{select_options.size()} options.\n"
                print "Perhaps you meant one of these? #{ored_list(select_options.collect {|i|i['name']}, 3)}\n"
                print "Please try again.\n"
              end
              print "\n"
              # reprompting now...
            end
          end
        end # end while !value_found

        # wrap in object when using fieldInput
        if value && !option_type['fieldInput'].nil?
          value = {option_type['fieldName'].split('.').last => value, option_type['fieldInput'] => (no_prompt ? option_type['defaultInputValue'] : field_input_prompt(option_type))}
        end
        value
      end

      # this is a funky one, the user is prompted for yes/no
      # but the return value is 'on','off',nil
      # todo: maybe make this easier to use, and have the api's be flexible too..
      # @param option_type [Hash] option type object with type,fieldName,fieldLabel,etc..
      # @return 'on', 'off' or nil
      def self.checkbox_prompt(option_type)
        value_found = false
        value = nil
        has_default = option_type['defaultValue'] != nil
        default_yes = has_default ? ['on', 'true', 'yes', '1'].include?(option_type['defaultValue'].to_s.downcase) : false
        while !value_found do
          print "#{option_type['fieldLabel']} (yes/no)#{has_default ? ' ['+(default_yes ? 'yes' : 'no')+']' : ''}: "
          input = $stdin.gets.chomp!
          if input == '?'
            help_prompt(option_type)
            next
          end
          if input.downcase == 'yes'
            value_found = true
            value = 'on'
          elsif input.downcase == 'no'
            value_found = true
            value = 'off'
          elsif input == '' && has_default
            value_found = true
            value = default_yes ? 'on' : 'off'
          end
          if value.nil? && option_type['required']
            puts "Invalid Option... Please try again."
            next
          end
          if value.nil? && !option_type['required']
            value_found = true
          end
        end
        return value
      end

      def self.field_input_prompt(option_type)
        value_found = false
        value = nil

        input_field_label = option_type['fieldInput'].gsub(/[A-Z]/, ' \0').split(' ').collect {|it| it.capitalize}.join(' ')
        input_field_name = option_type['fieldName'].split('.').reverse.drop(1).reverse.push(option_type['fieldInput']).join('.')
        input_option_type = option_type.merge({'fieldName' => input_field_name, 'fieldLabel' => input_field_label, 'required' => true, 'type' => 'text'})

        while !value_found do
          print "#{input_field_label}#{option_type['defaultInputValue'] ? " [#{option_type['defaultInputValue']}]" : ''}: "
          input = $stdin.gets.chomp!
          value = input.empty? ? option_type['defaultInputValue'] : input
          if input == '?'
            help_prompt(input_option_type)
          elsif !value.nil?
            value_found = true
          end
        end
        return value
      end

      def self.generic_prompt(option_type)
        value_found = false
        value = nil
        while !value_found do
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
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
            print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)} [Type 'EOF' to stop input]: \n"
          end
          input = $stdin.gets.chomp!
          # value = input.empty? ? option_type['defaultValue'] : input
          if input == '?' && value.nil?
            help_prompt(option_type)
          elsif input.chomp == '' && value.nil?
            # just hit enter right away to skip this
            value_found = true
          elsif input.chomp == 'EOF'
            value_found = true
          else
            if value.nil?
              value = ''
            end
            value << input + "\n"
          end
        end
        return value ? value.strip : value
      end

      def self.password_prompt(option_type)
        value_found = false
        while !value_found do
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)}#{option_type['defaultValue'] ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          input = $stdin.noecho(&:gets).chomp!
          value = input
          print "\n"
          if input == '?'
            help_prompt(option_type)
          elsif input == "" && option_type['defaultValue'] != nil
            value = option_type['defaultValue'].to_s
            value_found = true
          elsif !value.empty? || option_type['required'] != true
            value_found = true
          end
        end
        return value
      end

      def self.file_prompt(option_type)
        value_found = false
        value = nil
        while !value_found do
          #print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)}#{option_type['defaultValue'] ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          Readline.completion_append_character = ""
          Readline.basic_word_break_characters = ''
          Readline.completion_proc = proc {|s| Readline::FILENAME_COMPLETION_PROC.call(s) }
          input = Readline.readline("#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? (' (' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)}#{option_type['defaultValue'] ? ' ['+option_type['defaultValue'].to_s+']' : ''}: ", false).to_s
          input = input.chomp.strip
          #input = $stdin.gets.chomp!
          value = input.empty? ? option_type['defaultValue'] : input.to_s
          if input == '?'
            help_prompt(option_type)
          elsif value.empty? && option_type['required'] != true
            value = nil
            value_found = true
          elsif value
            filename = File.expand_path(value)
            if !File.exists?(filename)
              # print_red_alert "File not found: #{filename}"
              # exit 1
              print Term::ANSIColor.red,"  File not found: #{filename}",Term::ANSIColor.reset, "\n"
            elsif !File.file?(filename)
              print Term::ANSIColor.red,"  Argument is not a file: #{filename}",Term::ANSIColor.reset, "\n"
            else
              value = filename
              value_found = true
            end
          end
        end
        return value
      end

      # file_content_prompt() prompts for source (local,repository,url) and then content or repo or.
      # returns a Hash like {sourceType:"local",content:"yadda",contentPath:null,contentRef:null}
      def self.file_content_prompt(option_type, options={}, api_client=nil, api_params={})
        file_params = {}
        options ||= {}
        full_field_key = option_type['fieldContext'] ? "#{option_type['fieldContext']}.#{option_type['fieldName']}" : "#{option_type['fieldName']}"
        passed_file_params = get_object_value(options, full_field_key)
        if passed_file_params.is_a?(Hash)
          file_params = passed_file_params
        end
        is_required = option_type['required']
        if file_params['source']
          file_params['sourceType'] = file_params.delete('source')
        end
        source_type = file_params['sourceType']
        # source
        if source_type.nil?
          source_type = select_prompt({'fieldContext' => full_field_key, 'fieldName' => 'source', 'fieldLabel' => 'Source', 'type' => 'select', 'optionSource' => 'fileContentSource', 'required' => is_required, 'defaultValue' => (is_required ? 'local' : nil)}, api_client, {}, options[:no_prompt])
          file_params['sourceType'] = source_type
        end
        # source type options
        if source_type == "local"
          # prompt for content
          if file_params['content'].nil?
            if options[:no_prompt]
              print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
              print Term::ANSIColor.red, "  * Content [-O #{full_field_key}.content=] - File Content\n", Term::ANSIColor.reset
              print "\n"
              exit 1
            else
              file_params['content'] = multiline_prompt({'fieldContext' => full_field_key, 'fieldName' => 'content', 'type' => 'code-editor', 'fieldLabel' => 'Content', 'required' => true})
            end
          end
        elsif source_type == "url"
          if file_params['url']
            file_params['contentPath'] = file_params.delete('url')
          end
          if file_params['contentPath'].nil?
            if options[:no_prompt]
              print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
              print Term::ANSIColor.red, "  * URL [-O #{full_field_key}.url=] - Path of file in the repository\n", Term::ANSIColor.reset
              print "\n"
              exit 1
            else
              file_params['contentPath'] = generic_prompt({'fieldContext' => full_field_key, 'fieldName' => 'url', 'fieldLabel' => 'URL', 'type' => 'text', 'required' => true})
            end
          end
        elsif source_type == "repository"
          if file_params['repository'].nil?
            repository_id = select_prompt({'fieldContext' => full_field_key, 'fieldName' => 'repositoryId', 'fieldLabel' => 'Repository', 'type' => 'select', 'optionSource' => 'codeRepositories', 'required' => true}, api_client, {}, options[:no_prompt])
            file_params['repository'] = {'id' => repository_id}
          end
          if file_params['contentPath'].nil?
            if options[:no_prompt]
              print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
              print Term::ANSIColor.red, "  * File Path [-O #{full_field_key}.path=] - Path of file in the repository\n", Term::ANSIColor.reset
              print "\n"
              exit 1
            else
              file_params['contentPath'] = generic_prompt({'fieldContext' => full_field_key, 'fieldName' => 'path', 'fieldLabel' => 'File Path', 'type' => 'text', 'required' => true})
            end
          end
          if !file_params.key?('contentRef')
            if options[:no_prompt]
              # pass
            else
              file_params['contentRef'] = generic_prompt({'fieldContext' => full_field_key, 'fieldName' => 'ref', 'fieldLabel' => 'Version Ref', 'type' => 'text'})
            end
          end
        end
        return file_params
      end

      def self.load_options(option_type, api_client, api_params, query_value=nil)
        select_options = []
        # local array of options
        if option_type['selectOptions']
          # calculate from inline lambda
          if option_type['selectOptions'].is_a?(Proc)
            select_options = option_type['selectOptions'].call(api_client, api_params || {})
          else
            select_options = option_type['selectOptions']
          end
          # filter options ourselves
          if query_value.to_s != ""
            filtered_options = select_options.select { |it| it['value'].to_s == query_value.to_s }
            if filtered_options.empty?
              filtered_options = select_options.select { |it| it['name'].to_s == query_value.to_s }
            end
            select_options = filtered_options
          end
        elsif option_type['optionSource']
          api_params = api_params.select {|k,v| option_type['params'].include(k)} if option_type['params'].nil? && api_params

          # calculate from inline lambda
          if option_type['optionSource'].is_a?(Proc)
            select_options = option_type['optionSource'].call(api_client, api_params || {})
          elsif option_type['optionSource'] == 'list'
            # /api/options/list is a special action for custom OptionTypeLists, just need to pass the optionTypeId parameter
            select_options = load_source_options(option_type['optionSource'], option_type['optionSourceType'], api_client, api_params || {}.merge({'optionTypeId' => option_type['id']}))
          else
            # remote optionSource aka /api/options/$optionSource?
            select_options = load_source_options(option_type['optionSource'], option_type['optionSourceType'], api_client, api_params || {})
          end
        else
          raise "option '#{field_key}' is type: 'typeahead' and missing selectOptions or optionSource!"
        end

        return select_options
      end

      def self.help_prompt(option_type)
        field_key = [option_type['fieldContext'], option_type['fieldName']].select {|it| it && it != '' }.join('.')
        help_field_key = option_type[:help_field_prefix] ? "#{option_type[:help_field_prefix]}.#{field_key}" : field_key
        # an attempt at prompting help for natural options without the -O switch
        if option_type[:fmt] == :natural
          print Term::ANSIColor.green,"  * #{option_type['fieldLabel']} [--#{help_field_key}=] ", Term::ANSIColor.reset , "#{option_type['description']}\n"
        else
          print Term::ANSIColor.green,"  * #{option_type['fieldLabel']} [-O #{help_field_key}=] - ", Term::ANSIColor.reset , "#{option_type['description']}\n"
        end
        if option_type['type'].to_s == 'typeahead'
          print "This is a typeahead input. Enter the name or value of an option.\n"
          print "If the specified input matches more than one option, they will be printed and you will be prompted again.\n"
          print "the matching options will be shown and you can try again.\n"
        end
      end


      def self.load_source_options(source,sourceType,api_client,params)
        api_client.options.options_for_source("#{sourceType ? "#{sourceType}/" : ''}#{source}",params)['data']
      end

      def self.format_select_options_help(opt, select_options = [], paging = nil)
        out = ""
        header = opt['fieldLabel'] ? "#{opt['fieldLabel']} Options" : "Options"
        if paging
          offset = paging[:cur_page] * paging[:page_size]
          limit = [offset + paging[:page_size], select_options.count].min - 1
          header = "#{header} (#{offset+1}-#{limit+1} of #{paging[:total]})"
          select_options = select_options[(offset)..(limit)]
        end
        out = ""
        out << "\n"
        out << "#{header}\n"
        out << "#{'=' * header.length}\n"

        select_options.each do |option|
          out << (option['isGroup'] ? "- #{option['name']}\n" : " * #{option['name']} [#{option['value']}]\n")
        end
        return out
      end

      def self.sorted_option_types(option_types)
        option_types.reject {|it| (it['fieldGroup'] || 'default') != 'default'}.sort {|a,b| a['displayOrder'].to_i <=> b['displayOrder'].to_i} +
        option_types.reject {|it| ['default', 'advanced'].include?(it['fieldGroup'] || 'default')}.sort{|a,b| a['displayOrder'] <=> b['displayOrder']}.group_by{|it| it['fieldGroup']}.values.collect { |it| it.sort{|a,b| a['displayOrder'].to_i <=> b['displayOrder'].to_i}}.flatten +
        option_types.reject {|it| it['fieldGroup'] != 'advanced'}.sort {|a,b| a['displayOrder'].to_i <=> b['displayOrder'].to_i}
      end

      def self.display_select_options(opt, select_options = [], paging = nil)
        puts self.format_select_options_help(opt, select_options, paging)
      end

      def self.format_option_types_help(option_types, opts={})
        option_types = self.sorted_option_types(option_types).reject {|it| it['hidden']}

        if option_types.empty?
          "#{opts[:color]}#{opts[:title] || "Available Options:"}\nNone\n\n"
        else
          if opts[:include_context]
            option_lines = option_types.collect {|it|
              field_context = (opts[:context_map] || {})[it['fieldContext']] || it['fieldContext']
              "    -O #{field_context && field_context != '' ? "#{field_context}." : ''}#{it['fieldName']}=\"value\""
            }
          else
            option_lines = option_types.collect {|it| "    -O #{it['fieldName']}=\"value\"" }
          end
          "#{opts[:color]}#{opts[:title] || "Available Options:"}\n#{option_lines.join("\n")}\n\n"
        end
      end
        
      def self.display_option_types_help(option_types, opts={})
        puts self.format_option_types_help(option_types, opts)
      end

      def self.optional_label(option_type)
        # removing this for now, for the sake of providing less to look at
        if option_type[:fmt] == :natural # || true
          return ""
        else
          return option_type['required'] ? '' : ' (optional)'
        end
      end

      def self.get_option_value(obj, option_type, format=false)
        context = option_type['fieldContext'] == 'config' ? obj['config'] : obj
        name = option_type['fieldName']
        tokens = name.split('.')

        if tokens.length > 1
          tokens.slice(0, tokens.length - 1).each do |token|
            context = context[token]
          end
          name = tokens.last
        end

        if context.kind_of?(Array)
          rtn = context.collect {|it| it['name'] || it[name]}.join ', '
        else
          rtn = context[name]
        end

        if format
          rtn = (rtn ? 'On' : 'Off') if option_type['type'] == 'checkbox'
          rtn = rtn.join(', ') if rtn.is_a?(Array)
        end
        rtn
      end
    end
  end
end
