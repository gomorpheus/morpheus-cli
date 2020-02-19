require 'term/ansicolor'
require 'readline'
module Morpheus
  module Cli
    module OptionTypes
      include Term::ANSIColor

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

      def self.no_prompt(option_types, options={}, api_client=nil,api_params={})
        prompt(option_types, options, api_client, api_params, true)
      end

      def self.prompt(option_types, options={}, api_client=nil, api_params={}, no_prompt=false, paging_enabled=false)
        paging_enabled = false if Morpheus::Cli.windows?
        results = {}
        options = options || {}
        # puts "Options Prompt #{options}"
        option_types.sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |option_type|
          context_map = results
          value = nil
          value_found=false

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
          namespaces = field_key.split(".")
          field_name = namespaces.pop

          # respect optionType.dependsOnCode
          if option_type['dependsOnCode'] && option_type['dependsOnCode'] != ""
            # optionTypes can have this setting in the format code=value or code:value
            parts = option_type['dependsOnCode'].include?("=") ? option_type['dependsOnCode'].split("=") : option_type['dependsOnCode'].split(":")
            depends_on_code = parts[0]
            depends_on_value = parts[1]
            depends_on_option_type = option_types.find {|it| it["code"] == depends_on_code }
            # could not find the dependent option type, proceed and prompt
            if !depends_on_option_type.nil?
              # dependent option type has a different value
              depends_on_field_key = depends_on_option_type['fieldContext'] ? "#{depends_on_option_type['fieldContext']}.#{depends_on_option_type['fieldName']}" : "#{depends_on_option_type['fieldName']}"
              found_dep_value = get_object_value(results, depends_on_field_key) || get_object_value(options, depends_on_field_key)
              if depends_on_value && depends_on_value != found_dep_value
                next
              end
            end
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

          # use the value passed in the options map
          if cur_namespace.respond_to?('key?') && cur_namespace.key?(field_name)
            value = cur_namespace[field_name]
            input_value = ['select', 'multiSelect'].include?(option_type['type']) && option_type['fieldInput'] ? cur_namespace[option_type['fieldInput']] : nil
            if option_type['type'] == 'number'
              value = value.to_s.include?('.') ? value.to_f : value.to_i
            elsif ['select', 'multiSelect'].include?(option_type['type'])
              # this should just fall down through below, with the extra params no_prompt, use_value
              value = select_prompt(option_type.merge({'defaultValue' => value, 'defaultInputValue' => input_value}), api_client, (api_params || {}).merge(results), true)
            end
            if options[:always_prompt] != true
              value_found = true
            end
          end

          # set the value that has been passed to the option type default value: options[fieldContext.fieldName]
          if value != nil # && value != ''
            option_type = option_type.clone
            option_type['defaultValue'] = value
          end
          # no_prompt means skip prompting and instead
          # use default value or error if a required option is not present
          no_prompt = no_prompt || options[:no_prompt]
          if no_prompt
            if !value_found
              if option_type['defaultValue'] != nil && option_type['type'] != 'select'
                value = option_type['defaultValue']
                value_found = true
              end
              if !value_found
                # select type is special because it supports skipSingleOption
                # and prints the available options on error
                if ['select', 'multiSelect'].include?(option_type['type'])
                  value = select_prompt(option_type.merge({'defaultValue' => value}), api_client, (api_params || {}).merge(results), true)
                  value_found = !!value
                end
                if !value_found
                  if option_type['required']
                    print Term::ANSIColor.red, "\nMissing Required Option\n\n", Term::ANSIColor.reset
                    print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{field_key}=] - #{option_type['description']}\n", Term::ANSIColor.reset
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
              value = select_prompt(option_type, api_client, (api_params || {}).merge(results), options[:no_prompt], nil, paging_enabled)
              if value && option_type['type'] == 'multiSelect'
                value = [value]
                while self.confirm("Add another #{option_type['fieldLabel']}?", {:default => false}) do
                  if addn_value = select_prompt(option_type, api_client, (api_params || {}).merge(results), options[:no_prompt], nil, paging_enabled)
                    value << addn_value
                  else
                    break
                  end
                end
              end
            elsif option_type['type'] == 'hidden'
              value = option_type['defaultValue']
              input = value
            elsif option_type['type'] == 'file'
              value = file_prompt(option_type)
            else
              value = generic_prompt(option_type)
            end
          end

          if option_type['type'] == 'multiSelect'
            value = [value] if !value.nil? && !value.is_a?(Array)
            parent_context_map[parent_ns] = value
          else
            context_map[field_name] = value
          end
        end
        results
      end

      def self.grails_params(data, context=nil)
        params = {}
        data.each do |k,v|
          if v.is_a?(Hash)
            params.merge!(grails_params(v, context ? "#{context}.#{k.to_s}" : k))
          else
            if context
              params["#{context}.#{k.to_s}"] = v
            else
              params[k.to_s] = v
            end
          end
        end
        return params
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
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          input = $stdin.gets.chomp!
          value = input.empty? ? option_type['defaultValue'] : input
          value = value.to_s.include?('.') ? value.to_f : value.to_i
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
        value_found = false
        value = nil
        value_field = (option_type['config'] ? option_type['config']['valueField'] : nil) || 'value'
        default_value = option_type['defaultValue']
        default_value = default_value['id'] if default_value && default_value.is_a?(Hash) && !default_value['id'].nil?
        # local array of options
        if option_type['selectOptions']
          # calculate from inline lambda
          if option_type['selectOptions'].is_a?(Proc)
            select_options = option_type['selectOptions'].call()
          else
            # todo: better type validation
            select_options = option_type['selectOptions']
          end
        elsif option_type['optionSource']
          # calculate from inline lambda
          if option_type['optionSource'].is_a?(Proc)
            select_options = option_type['optionSource'].call()
          elsif option_type['optionSource'] == 'list'
            # /api/options/list is a special action for custom OptionTypeLists, just need to pass the optionTypeId parameter
            select_options = load_source_options(option_type['optionSource'], api_client, {'optionTypeId' => option_type['id']})
          else
            # remote optionSource aka /api/options/$optionSource?
            select_options = load_source_options(option_type['optionSource'], api_client, grails_params(api_params || {}))
          end
        else
          raise "select_prompt() requires selectOptions or optionSource!"
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
              puts " (#{select_options.size-1} more)"
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
            found_default_option  = select_options.find {|opt| opt[value_field].to_s == default_value.to_s}
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
              print Term::ANSIColor.red, "  * #{option_type['fieldLabel']} [-O #{option_type['fieldContext'] ? (option_type['fieldContext']+'.') : ''}#{option_type['fieldName']}=] - #{option_type['description']}\n", Term::ANSIColor.reset
              if select_options && select_options.size > 10
                display_select_options(option_type, select_options.first(10))
                puts " (#{select_options.size-1} more)"
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
          input = Readline.readline("#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!default_value.to_s.empty? ? ' ['+default_value.to_s+']' : ''} ['?' for#{has_more_pages && paging[:cur_page] > 0 ? ' more ' : ' '}options]: ", false).to_s
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
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{!option_type['required'] ? ' (optional)' : ''}#{!option_type['defaultValue'].to_s.empty? ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
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
            print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)} [Type 'EOF' to stop input]: \n"
          end
          input = $stdin.gets.chomp!
          # value = input.empty? ? option_type['defaultValue'] : input
          if input == '?' && value.nil?
            help_prompt(option_type)
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
          print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)}#{option_type['defaultValue'] ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
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
          #print "#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)}#{option_type['defaultValue'] ? ' ['+option_type['defaultValue'].to_s+']' : ''}: "
          Readline.completion_append_character = ""
          Readline.basic_word_break_characters = ''
          Readline.completion_proc = proc {|s| Readline::FILENAME_COMPLETION_PROC.call(s) }
          input = Readline.readline("#{option_type['fieldLabel']}#{option_type['fieldAddOn'] ? ('(' + option_type['fieldAddOn'] + ') ') : '' }#{optional_label(option_type)}#{option_type['defaultValue'] ? ' ['+option_type['defaultValue'].to_s+']' : ''}: ", false).to_s
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

      def self.help_prompt(option_type)
        full_field_name = option_type['fieldContext'] && option_type['fieldContext'] != '' ? (option_type['fieldContext']+'.') : ''
        full_field_name << option_type['fieldName'].to_s
        # an attempt at prompting help for natural options without the -O switch
        if option_type[:fmt] == :natural
          print Term::ANSIColor.green,"  * #{option_type['fieldLabel']} [--#{full_field_name}=] ", Term::ANSIColor.reset , "#{option_type['description']}\n"
        else
          print Term::ANSIColor.green,"  * #{option_type['fieldLabel']} [-O #{full_field_name}=] - ", Term::ANSIColor.reset , "#{option_type['description']}\n"
        end
      end


      def self.load_source_options(source,api_client,params)
        api_client.options.options_for_source(source,params)['data']
      end

      def self.display_select_options(opt, select_options = [], paging = nil)
        header = opt['fieldLabel'] ? "#{opt['fieldLabel']} Options" : "Options"
        if paging
          offset = paging[:cur_page] * paging[:page_size]
          limit = [offset + paging[:page_size], select_options.count].min - 1
          header = "#{header} (#{offset+1}-#{limit+1} of #{paging[:total]})"
          select_options = select_options[(offset)..(limit)]
        end
        puts "\n#{header}"
        puts "==============="
        select_options.each do |option|
          puts " * #{option['name']} [#{option['value']}]"
        end
      end

      def self.format_option_types_help(option_types, opts={})
        if option_types.empty?
          "#{opts[:color]}#{opts[:title] || "Available Options:"}\nNone\n\n"
        else
          if opts[:include_context]
            option_lines = option_types.sort {|it| it['displayOrder']}.collect {|it|
              field_context = (opts[:context_map] || {})[it['fieldContext']] || it['fieldContext']
              "    -O #{field_context && field_context != '' ? "#{field_context}." : ''}#{it['fieldName']}=\"value\""
            }
          else
            option_lines = option_types.sort {|it| it['displayOrder']}.collect {|it| "    -O #{it['fieldName']}=\"value\"" }
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
    end
  end
end
