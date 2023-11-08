require 'morpheus/cli/option_types'

# Mixin for Morpheus::Cli command classes
# Provides common methods for prompting for option type inputs and forms.
# Prompting is delegated to the {Morpheus::Cli::OptionTypes} module
# while the provided {#prompt} simplifies the required parameters
# The command class must establish the +@api_client+ on its own.
#
module Morpheus::Cli::PromptHelper

  # Prompt for a list of inputs (OptionType) and return a Hash containing
  # all of the provides values.  The user is prompted to provide a value 
  # for each input, unless the value is already set in the options.
  # @param [Array, Hash] option_types the list of OptionType inputs with fieldName, fieldLabel, etc.
  #   A single option type Hash can be passed instead.
  # @param [Hash] options the standard command options
  #   This map is a mixture of keys that are Symbols that provide some common
  #   functionality like :no_prompt, :context_map, etc.
  #   Any keys that are Strings get used to lookup input values, along with 
  #   +options[:options]+ and +options[:params]+.
  #   The precedence for providing option values is as follows: 
  #   1. options['foo']  2. options[:params]['foo'] 3. options[:options]['foo'] 4. User is prompted.
  # @option options [Hash] :options map of values provided by the user via the generic -O OPTIONS switch, gets merged into the context used for providing input values
  # @option options [Hash] :params map of additional values provided by the user via explicite options, gets merged into the context used for providing input values
  # @option options [Hash] :no_prompt supresses prompting, use default values and error if a required input is not provided. Default is of course +false+.
  # @option options [Hash] :context_map Can to change the fieldContext of the option_types, eg. :context_map => {'networkDhcpRelay' => ''}
  # @option options [APIClient] :api_client The {APIClient} to use for option types that request api calls. Default is the @api_client established by the class
  # @option options [Hash] :api_params Optional map of parameters to include in API request for select option types
  # @option options [Boolean] :paging_enabled Enable paging if there are a lot of available options to display. Default is +false+.
  # @option options [Boolean] :ignore_empty Ignore inputs that have no options, this can be used to allow prompting to continue without error if a select input has no options.
  # @option options [Boolean] :skip_sort Do not sort the inputs by displayOrder, assume they are already sorted. Default is +true+.
  # @return [Hash] containing the values provided for each option type, the key is the input fieldName
  #
  # @example Prompt for name
  #
  #   results = prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options)
  #   puts "Name: #{results['name']}"
  #
  def prompt(option_types, options={})
    # option types can be passed as a single input instead of an array
    option_types = option_types.is_a?(Hash) ? [option_types] : option_types #Array(option_types)
    # construct options parameter for Morpheus::Cli::OptionTypes.prompt
    options = construct_prompt_options(options)
    # by default the @api_client established by the command is used
    api_client = options.key?(:api_client) ? options[:api_client] : @api_client
    api_params = options.key?(:api_params) ? options[:api_params] : {}
    no_prompt = options.key?(:no_prompt) ? options[:no_prompt] : false
    paging_enabled = options.key?(:paging_enabled) ? options[:paging_enabled] : false
    ignore_empty = options.key?(:ignore_empty) ? options[:ignore_empty] : false
    # Defaulting skip_sort to true which is the opposite of OptionTypes.prompt()
    # The API handles sorting most of the time now, calling function can sort before prompting if needed
    # maybe switch this later if needed, removing skip_sort would be nice though...
    skip_sort = options.key?(:skip_sort) ? options[:skip_sort] : true
    results = Morpheus::Cli::OptionTypes.prompt(option_types, options, api_client, api_params, no_prompt, paging_enabled, ignore_empty, skip_sort)
    # trying to get rid of the need to do these compact and booleanize calls..
    # for now you can use options.merge({compact: true,booleanize: true}) or modify the results yourself
    results.deep_compact! if options[:compact]
    results.booleanize! if options[:booleanize] # 'on' => true
    return results
  end

  # Process 1-N inputs (OptionType) in a special 'edit mode' that supresses user interaction.
  # This is used by +update+ commands where we want to process option types
  # without prompting the user so that the results only contains values that are passed in explicitely as options and default values are not used.
  # @see {#prompt} method for details on the supported options
  #
  def no_prompt(option_types, options={})
    options = options.merge({:edit_mode => true, :no_prompt => true})
    options.delete(:no_prompt) if options[:always_prompt] # --prompt to always prompt
    return prompt(option_types, options)
  end

  # Prompt for a single input and return only the value
  # @param [Hash] option_type the OptionType input record to prompt for, contains fieldName, fieldLabel, etc.
  # @param [Hash] options the standard command options
  # @see {#prompt} method for details on the supported options
  # @return [String, Number, Hash, Array, nil] value provided by the options or user input, usually a string or a number or nil if no value is provided.
  #
  # @example Prompt for name value
  #
  #   chosen_name = prompt_value({'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}, options)
  #   puts "Chosen Name: #{chosen_name}"
  #
  def prompt_value(option_type, options={})
    # this does not need with fieldContext, so get rid of it
    # option_types = [option_type.merge({'fieldContext' => nil})]
    # results = prompt(Array(option_type), options)
    # return results[option_type['fieldName']]

    # this works with fieldContext now, hooray
    # use get_object_value() to traverse object to get the value
    option_types = [option_type] # Array(option_type)
    results = prompt(option_types, options)
    return get_option_type_value(results, option_types.first)
  end

  # Process inputs of a form, prompting for its options and field groups
  # @param [Hash] form the OptionTypeForm to process
  # @param [Hash] options the standard command options
  # @see {#prompt} method for defailts on the supported options
  # @return Hash containing the values provided for each option type, the key is the fieldName
  #
  def prompt_form(form, options={})
    form_results = {}
    results = prompt(Array(form['options']), options.merge(form_results))
    form_results.deep_merge!(results)
    # prompt for each field group, merging results into options context as we go
    Array(form['fieldGroups']).each do |field_group|
      # todo: look at isCollapsible, defaultCollapsed and visibleOnCode to see if the group should
      # if collapsed then just use options.merge({:no_prompt => true}) and maybe need to set :required => false ?
      results = prompt(field_group['options'], options.merge(form_results))
      form_results.deep_merge!(results)
    end
    return form_results
  end

  protected

  # construct options parameter for Morpheus::Cli::OptionTypes.prompt
  # This options Hash is a mixture of Symbols that provide some common functionality like :no_prompt, and :context_map, etc.
  # String keys are used to lookup values being passed into the command in order to prevent prompting the user
  # The precedence for providing option values is as follows: 
  #   1. options['foo']  2. options[:params]['foo'] 3. options[:options]['foo']
  #
  def construct_prompt_options(options)
    passed_options = Hash(options[:options]).select {|k,v| k.is_a?(String) }
    params = Hash(options[:params]).select {|k,v| k.is_a?(String) }
    return passed_options.deep_merge(params).deep_merge!(options)
  end

  def get_option_type_value(results, option_type)
    field_key = [option_type['fieldContext'], option_type['fieldName']].select {|it| it && it != '' }.join('.')
    get_object_value(results, field_key)
  end

end