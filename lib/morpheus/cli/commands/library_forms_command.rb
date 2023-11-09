require 'morpheus/cli/cli_command'
require 'securerandom'
  
class Morpheus::Cli::LibraryFormsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::LibraryHelper

  set_command_name :'library-forms'
  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @library_instance_types_interface = @api_client.library_instance_types
    @provision_types_interface = @api_client.provision_types
    @option_types_interface = @api_client.option_types
    @option_type_forms_interface = @api_client.option_type_forms
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on('-l', '--labels LABEL', String, "Filter by labels, can match any of the values") do |val|
        add_query_parameter(params, 'labels', parse_labels(val))
      end
      opts.on('--all-labels LABEL', String, "Filter by labels, must match all of the values") do |val|
        add_query_parameter(params, 'allLabels', parse_labels(val))
      end
      build_standard_list_options(opts, options)
      opts.footer = "List option forms."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    params.merge!(parse_list_options(options))
    @option_type_forms_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @option_type_forms_interface.dry.list(params)
      return
    end
    json_response = @option_type_forms_interface.list(params)
    render_response(json_response, options, rest_list_key) do
      option_type_forms = json_response[rest_list_key]
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Forms", subtitles, options
      if option_type_forms.empty?
        print cyan,"No forms found.",reset,"\n"
      else
        rows = option_type_forms.collect do |option_type_form|
          {
            id: option_type_form['id'],
            name: option_type_form['name'],
            labels: option_type_form['labels'],
            description: option_type_form['description'],
          }
        end
          columns = [
          :id,
          :name,
          {:labels => {:display_method => lambda {|it| format_list(it[:labels], '', 3) rescue '' }}},
          :description,
        ]
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[form]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a form.
[form] is required. This is the name or id of a form.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end
  
  def _get(id, options)
    params = {}
    params.merge!(parse_query_options(options))
    if id.to_s !~ /\A\d{1,}\Z/
      # option_type_form = find_by_name(:option_type_form, id)
      option_type_form = find_option_type_form_by_name_or_id(id)
      return 1, "Form not found" if option_type_form.nil?
      id = option_type_form['id']
    end
    @option_type_forms_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @option_type_forms_interface.dry.get(id.to_i, params)
      return
    end
    json_response = @option_type_forms_interface.get(id.to_i, params)
    render_response(json_response, options, rest_object_key) do
      option_type_form = json_response[rest_object_key]
      print_h1 "Form Details", options
      print cyan
      print_description_list({
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Labels" => lambda {|it| format_list(it['labels']) },
      }, option_type_form, options)
      
      # show option types
      print_h2 "Form Inputs"
      #print format_option_types_table(option_type_form['options'], options, nil, true)
      print format_option_types_table(option_type_form['options'], options, 'config.customOptions')
      print reset,"\n"

      # show Field Groups
      field_groups = option_type_form['fieldGroups']
      if field_groups && field_groups.size > 0
        field_groups.each do |field_group|
          print_h2 "#{field_group['name']}"
          #print format_option_types_table(field_group['options'], options, nil, true)
          if field_group['options'] && !field_group['options'].empty?
            print format_option_types_table(field_group['options'], options, 'config.customOptions')
            print reset,"\n"
          else
            print cyan, "This field group is empty", reset, "\n\n"
          end
        end
      end
    end
  end

  def add(args)
    options = {}
    my_option_types = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, new_option_type_form_option_types())
      # maybe use --inputs for less confusion
      opts.on('--options OPTIONS', String, "List of option type inputs to add to the form, this list can include full JSON objects or just the id to use an existing option eg. --options '[5,6,7,{\"fieldName\":\"input\",\"fieldLabel\":\"Input\"}]'") do |val|
        val = "[#{val.strip}]" unless val.strip.to_s[0] == '[' && val.strip.to_s[-1] == ']'
        begin
          options[:selected_options] = JSON.parse(val)
        rescue
          raise_command_error "Failed to parse --options value '#{val}' as JSON"
        end
      end
      build_standard_add_options(opts, options)
      opts.footer = "Create a new form."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    if args.count == 1
      options[:options]['name'] = args[0]
    end
    connect(options)
    parse_payload(options, rest_object_key) do |payload|
      form_payload = prompt_new_form(options)
      #form_payload.deep_compact!.booleanize! # remove empty values and convert checkbox "on" and "off" to true and false
      payload.deep_merge!({rest_object_key => form_payload})
      # cleanup payload
      # remove transient option params used for prompting for list of inputs
      payload[rest_object_key].keys.each do |k|
        if k == "option" || k.to_s =~ /^option\d+$/ || k == "fieldGroup" || k.to_s =~ /^fieldGroup\d+$/
          payload[rest_object_key].delete(k)
        end
      end
    end
    execute_api(@option_type_forms_interface, :create, [], options, rest_object_key) do |json_response|
      form = json_response[rest_object_key]
      print_green_success "Added form #{form['name']}"
      _get(form['id'], options)
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[form] [options]")
      build_option_type_options(opts, options, update_option_type_form_option_types())
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a form.
[form] is required. This is the name or id of a form.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    form = find_option_type_form_by_name_or_id(args[0])
    return 1, "Form not found" if form.nil?
    parse_payload(options, rest_object_key) do |payload|
      option_types = update_option_type_form_option_types()
      v_prompt = no_prompt(option_types, options)
      #v_prompt.deep_compact!.booleanize! # remove empty values and convert checkbox "on" and "off" to true and false
      payload.deep_merge!({rest_object_key => v_prompt})
      if payload[rest_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    execute_api(@option_type_forms_interface, :update, [form['id']], options, 'backup') do |json_response|
      form = json_response[rest_object_key]
      print_green_success "Updated form #{form['name']}"
      _get(form['id'], options.merge(params:{}))
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[form]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a form.
[form] is required. This is the name or id of a form.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    form = find_option_type_form_by_name_or_id(args[0])
    return 1, "Form not found" if form.nil?
    parse_options(options, params)
    confirm!("Are you sure you want to delete the form #{form['name']}?", options)
    execute_api(@option_type_forms_interface, :destroy, [form['id']], options) do |json_response|
      print_green_success "Removed form #{form['name']}"
    end
  end

  private

  def rest_list_key
    option_type_form_list_key
  end

  def rest_object_key
    option_type_form_object_key
  end

  def option_type_form_list_key
    "optionTypeForms"
  end

  def option_type_form_object_key
    "optionTypeForm"
  end

  def find_option_type_form_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_option_type_form_by_id(val)
    else
      return find_option_type_form_by_name(val)
    end
  end

  def find_option_type_form_by_id(id)
    begin
      json_response = @option_type_forms_interface.get(id.to_i)
      return json_response[option_type_form_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Form not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_option_type_form_by_name(name)
    json_results = @option_type_forms_interface.list({name: name.to_s})
    records = json_results[option_type_form_list_key]
    if json_results['optionTypeForms'].empty?
      print_red_alert "Form not found by name '#{name}'"
      return nil
    elsif records.size > 1
      print_red_alert "More than one #{label.downcase} found by name '#{val}'"
      print_error "\n"
      puts_error as_pretty_table(records, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    end
    option_type_form = json_results['optionTypeForms'][0]
    return option_type_form
  end

  # def get_available_option_list_types
  #   [
  #     {'name' => 'REST', 'value' => 'rest'}, 
  #     {'name' => 'Morpheus Api', 'value' => 'api'}, 
  #     {'name' => 'LDAP', 'value' => 'ldap'}, 
  #     {'name' => 'Manual', 'value' => 'manual'}
  #   ]
  # end

  # def find_option_list_type(code)
  #    get_available_option_list_types.find {|it| code == it['value'] || code == it['name'] }
  # end

  def new_option_type_form_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Form name'},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => true, 'description' => 'Unique form code'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'shorthand' => '-l', 'fieldName' => 'labels', 'fieldLabel' => 'Labels', 'type' => 'text', 'required' => false, 'noPrompt' => true, 'processValue' => lambda {|val| parse_labels(val) }},
    ]
  end

  def update_option_type_form_option_types()
    list = new_option_type_form_option_types()
    list.each {|it| 
      it.delete('required')
      it.delete('defaultValue')
      it.delete('skipSingleOption')
    }
    list
  end

  # CLI Form builder

  def prompt_new_form(options)
    form_payload = {}
    form_payload = prompt(new_option_type_form_option_types(), options)
    # prompt for options
    form_payload['options'] = prompt_new_form_options(options)
    form_payload['fieldGroups'] = prompt_new_field_groups(options)

    return form_payload
  end

  # prompts user to define a list of new option types
  # returns array of option type objects {'fieldName' => "input1", 'fieldLabel' => "Input 1"}
  def prompt_new_form_options(options={}, field_group_context=nil)
    #puts "Source Headers:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    option_types = []
    i = 0
    field_context = "option#{i+1}"
    context_value_map = options[:options] # should just be options or options.deep_merge(options[:options] || {})
    if field_group_context
      context_value_map = context_value_map ? (context_value_map[field_group_context] || {}) : {}
    end
    selected_options = options[:selected_options] || [] # user passing in --options '[42,{"fieldName":"foo","fieldLabel":"Foo"}]'
    # puts "selected_options: #{selected_options.inspect}"
    has_another_option_type = context_value_map[field_context] || selected_options[0]
    add_another_option_type = has_another_option_type || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add an Input?", {default: true}))
    while add_another_option_type do
      print_h2 "Input #{i+1}"
      full_context = [field_group_context, field_context].select {|it| it.to_s != "" }.join('.')
      option_type = prompt_new_option_type(options, selected_options[i], full_context)
      print "\n"
      option_types << option_type
      i += 1
      field_context = "option#{i+1}"
      has_another_option_type = context_value_map && context_value_map[field_context]
      add_another_option_type = has_another_option_type || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another Input?", {default: false}))
    end

    return option_types
  end

  def prompt_new_option_type(options, selected_value=nil, field_context=nil)
    option_type = {}
    if selected_value
      if selected_value.is_a?(Hash)
        option_type = selected_value
      else
        existing_option_type = find_option_type_by_name_or_id(selected_value)
        raise_command_error "Option Type not found for '#{selected_value}'" if existing_option_type.nil?
        option_type['id'] = existing_option_type['id']
      end
      return option_type
    end
    # Use Existing Input? then skip all other inputs
    # context_value_map = field_context ? (options[:options][field_context] || {}) : {}
    context_value_map = field_context ? get_object_value(options[:options], field_context) : options[:options]
    if context_value_map && context_value_map['id']
      context_value_map['existing'] = "on"
    end
    use_existing = prompt_value({'fieldContext' => field_context, 'fieldName' => 'existing', 'fieldLabel' => 'Use Existing', 'type' => 'checkbox', 'required' => true, 'defaultValue' => false, 'description' => "Use an existing input instead of customizing a new one for this form"}, options)
    if use_existing.to_s == "on" || use_existing.to_s == "yes" || use_existing.to_s == "true"
      existing_id = prompt_value({'fieldContext' => field_context, 'fieldName' => 'id', 'fieldLabel' => 'Existing Input', 'type' => 'select', 'optionSource' => 'optionTypes', 'required' => true, 'description' => "Choose an existing input"}, options)
      option_type['id'] = existing_id.to_i
    else
      # prompt for a new option type
      option_types = new_form_input_option_types
      option_types.each {|it| it['fieldContext'] = field_context }
      results = prompt(option_types, options)
      results.booleanize! #.deep_compact!
      # option_type = field_context ? results[field_context] : results
      option_type = field_context ? get_object_value(results, field_context) : results
    end
    return option_type
  end

  # prompts user to define a list of field groups and their options
  # returns array of option type objects {'fieldName' => "input1", 'fieldLabel' => "Input 1"}
  def prompt_new_field_groups(options={})
    #puts "Source Headers:"
    no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
    field_groups = []
    selected_field_groups = options[:selected_field_groups] || [] # user passing in --options '[42,{"fieldName":"foo","fieldLabel":"Foo"}]'
    # puts "selected_field_groups: #{selected_field_groups.inspect}"
    i = 0
    field_context = "fieldGroup#{i+1}"
    has_another_field_group = options[:options][field_context] || selected_field_groups[0]
    add_another_field_group = has_another_field_group || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add a Field Group?", {default: false}))
    while add_another_field_group do
      print_h2 "Field Group #{i+1}"
      field_group = prompt_new_field_group(options, selected_field_groups[i], field_context)
      print "\n"
      field_groups << field_group
      i += 1
      field_context = "fieldGroup#{i+1}"
      has_another_field_group = options[:options] && options[:options][field_context]
      add_another_field_group = has_another_field_group || (!no_prompt && Morpheus::Cli::OptionTypes.confirm("Add another Field Group?", {default: false}))
    end

    return field_groups
  end

  def prompt_new_field_group(options, selected_value=nil, field_context=nil)
    field_group = {}
    # if selected_value
    #   if selected_value.is_a?(Hash)
    #     field_group = selected_value
    #   end
    #   return field_group
    # end
    
    # prompt for a field group
    field_group_option_types = [    
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'This field sets the name attribute for the field group.', 'defaultValue' => 'new fieldgroup'},
      # {'fieldName' => 'code', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'This field sets the code attribute for the field group.', 'defaultValue' => SecureRandom.uuid},
      # {'fieldName' => 'localizedName', 'fieldLabel' => 'Localized Name', 'type' => 'typeahead', 'optionSource' => 'messageCodes', 'description' => 'i18n code for the name'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'This field sets the name attribute for the input.'},
      {'fieldName' => 'collapsible', 'fieldLabel' => 'Collapsible', 'type' => 'checkbox', 'defaultValue' => true, 'description' => 'Field group is collapsible'},
      {'fieldName' => 'defaultCollapsed', 'fieldLabel' => 'Default Collapsed', 'type' => 'checkbox', 'defaultValue' => true, 'description' => 'Collapse field group by default'},
      {'fieldName' => 'visibleOnCode', 'fieldLabel' => 'Visibility Field', 'type' => 'text', 'description' => 'A fieldName that will trigger visibility of this field group'},
    ]
    field_group_option_types.each {|it| it['fieldContext'] = field_context }
    results = prompt(field_group_option_types, options)
    results.booleanize! #.deep_compact!
    field_group = field_context ? results[field_context] : results
    field_group['code'] = SecureRandom.uuid unless field_group['code']
    # prompt for options
    field_group['options'] = prompt_new_form_options(options, field_context)

    return field_group
  end

  # not used yet
  def prompt_edit_form(form, params, options)
    form_payload = {}
    selected_options = options[:selected_options] || [] # user passing in --options [42,{"fieldName":"foo","fieldLabel":"Foo"}]
    # this prompts for an action for each option on the list: keep, edit, remove
    new_options = []
    Array(form['options']).each_with_index do |option_type, i|

      field_context = i == 0 ? "option" : "option#{i+1}"
      results = prompt_edit_option_type(option_type, options, selected_options[i], field_context)
      if results.nil?
        # deleted
        next
      end
      new_options << results[field_context]
    end
    form_payload['options'] = new_options

    # todo: fieldGroups
    Array(form['fieldGroups']).each do |option_type|
    end

    
    return form_payload
  end

  def prompt_edit_option_type(current_option_type, options, selected_value=nil, field_context=nil)
    option_type = {'id' => current_option_type['id']}
    # if selected_value
    #   if selected_value.is_a?(Hash)
    #     option_type = selected_value
    #   else
    #     existing_option_type = find_option_type_by_name_or_id(selected_value)
    #     raise_command_error "Option Type not found for '#{selected_value}'" if existing_option_type.nil?
    #     option_type['id'] = existing_option_type['id']
    #   end
    #   return option_type
    # end

    action_options = [{'name' => 'Modify', 'value' => 'modify'}, {'name' => 'Keep', 'value' => 'keep'}, {'name' => 'Delete', 'value' => 'delete'}]
    v_prompt = prompt([{'fieldContext' => field_context, 'fieldName' => 'action', 'type' => 'select', 'fieldLabel' => "Modify/Keep/Delete Input '#{current_option_type['fieldLabel']}' (ID: #{current_option_type['id']})", 'selectOptions' => action_options, 'required' => true, 'defaultValue' => 'keep', 'description' => 'Modify, Keep or Remove form input?'}], options[:options])
    action = v_prompt[field_context]['action']

    if action == 'delete'
      # deleted input is just excluded from list
      option_type = nil
    elsif action == 'keep'
      # no changes
    elsif action == 'modify'
      # Modify existing input

      # Use Existing Input? 
      # If yes then then skip all other inputs
      if options[:options][field_context] && options[:options][field_context]['id']
        options[:options][field_context]['existing'] = "on"
      end
      use_existing = prompt_value({'fieldContext' => field_context, 'fieldName' => 'existing', 'fieldLabel' => 'Use Existing', 'type' => 'checkbox', 'required' => true, 'defaultValue' => (current_option_type['formField'] ? false : true), 'description' => "Use an existing input instead of customizing a new one for this form"}, options)
      if use_existing.to_s == "on" || use_existing.to_s == "yes" || use_existing.to_s == "true"
        existing_id = prompt_value({'fieldContext' => field_context, 'fieldName' => 'id', 'fieldLabel' => 'Existing Input', 'type' => 'select', 'optionSource' => 'optionTypes', 'required' => true, 'defaultValue' => (current_option_type['formField'] ? nil : current_option_type['name']), 'description' => "Choose an existing input"}, options)
        option_type['id'] = existing_id.to_i
      else
        # prompt to edit the existing option type
        option_types = update_form_input_option_types
        option_types.each {|it| it['fieldContext'] = field_context }
        results = prompt(option_types, options)
        results.booleanize! #.deep_compact!
        if field_context
          results = results[field_context]
        end
        option_type.deep_merge!(results) if results
      end
    end

    return option_type
  end

  def new_form_input_option_types()
    [
      {'code' => 'optionType.type', 'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => get_available_form_input_types(), 'defaultValue' => 'text', 'required' => true},
      {'fieldName' => 'optionList', 'fieldLabel' => 'Option List', 'type' => 'select', 'optionSource' => 'optionTypeLists', 'required' => true, 'dependsOnCode' => 'optionType.type:select', 'description' => "The Option List to be the source of options when type is 'select'."},
      {'fieldName' => 'fieldLabel', 'fieldLabel' => 'Field Label', 'type' => 'text', 'required' => true, 'description' => 'This is the input label that shows typically to the left of a custom option.'},
      {'fieldName' => 'fieldCode', 'fieldLabel' => 'Localized Label', 'type' => 'typeahead', 'optionSource' => 'messageCodes', 'description' => 'i18n code for the label'},
      {'fieldName' => 'fieldName', 'fieldLabel' => 'Field Name', 'type' => 'text', 'required' => true, 'description' => 'This field sets the name attribute for the input.'},
      {'fieldName' => 'defaultValue', 'fieldLabel' => 'Default Value', 'type' => 'text'},
      {'fieldName' => 'placeHolder', 'fieldLabel' => 'Placeholder', 'type' => 'text', 'description' => 'Text that is displayed when the field is empty'},
      {'fieldName' => 'helpBlock', 'fieldLabel' => 'Help Block', 'type' => 'text', 'description' => 'This is the explaination of the input that shows typically underneath the option.'},
      {'fieldName' => 'helpBlockFieldCode', 'fieldLabel' => 'Localized Help Block', 'type' => 'typeahead', 'optionSource' => 'messageCodes', 'description' => 'i18n code for the help block'},
      {'fieldName' => 'required', 'fieldLabel' => 'Required', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'exportMeta', 'fieldLabel' => 'Export As Tag', 'type' => 'checkbox', 'defaultValue' => false, 'description' => 'Export as Tag'},
      {'fieldName' => 'displayValueOnDetails', 'fieldLabel' => 'Display Value On Details', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'isLocked', 'fieldLabel' => 'Locked', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'isHidden', 'fieldLabel' => 'Hidden', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'excludeFromSearch', 'fieldLabel' => 'Exclude From Search', 'type' => 'checkbox', 'defaultValue' => false},
      # Advanced
      {'fieldName' => 'dependsOnCode', 'fieldLabel' => 'Dependent Field', 'type' => 'text', 'description' => 'A fieldName that will trigger reloading this input'},
      {'fieldName' => 'visibleOnCode', 'fieldLabel' => 'Visibility Field', 'type' => 'text', 'description' => 'A fieldName that will trigger visibility of this input'},
      {'fieldName' => 'verifyPattern', 'fieldLabel' => 'Verify Pattern', 'type' => 'text', 'dependsOnCode' => 'optionType.type:text', 'description' => 'A regexp string that validates the input, use (?i) to make the matcher case insensitive'},
      {'fieldName' => 'requireOnCode', 'fieldLabel' => 'Require Field', 'type' => 'text', 'description' => 'A fieldName that will trigger required attribute of this input'},
    ]
  end

  def update_form_input_option_types()
    list = new_option_type_form_option_types()
    list.each {|it| 
      it.delete('required')
      it.delete('defaultValue')
      it.delete('skipSingleOption')
    }
    list
  end

  def get_available_form_input_types()
    {
      checkbox: "Checkbox",
      hidden: "Hidden",
      number: "Number",
      password: "Password",
      radio: "Radio",
      select: "Select List",
      text: "Text",
      textarea: "Textarea",
      byteSize: "Byte Size",
      'code-editor': "Code Editor",
      fileContent: "File Content",
      logoSelector: "Icon Picker",
      keyValue: "Key Value",
      textArray: "Text Array",
      typeahead: "Typeahead",
      cloud: "Cloud",
      diskManager: "Disks",
      environment: "Environment",
      ports: "Exposed Ports",
      group: "Group",
      'instances-input': "Instances",
      layout: "Layout",
      networkManager: "Networks",
      plan: "Plan",
      resourcePool: "resourcePool",
      secGroup: "Security Groups",
      'servers-input': "Servers",
      'virtual-image': "Virtual Image",
      vmwFolders: "Vmw Folders",
      httpHeader: "Headers",
    }.collect {|k,v| {'name' => v.to_s, 'value' => k.to_s } }
  end
end
