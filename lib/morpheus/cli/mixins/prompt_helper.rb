# Mixin for Morpheus::Cli command classes
# Provides common methods for prompting for input
module Morpheus::Cli::PromptHelper

	# prompt for a single option type and and return the input value
	# @param option_type [Hash] The OptionType input record to prompt for , contians fieldName, fieldLabel, etc.
  # @param options [Hash] The context being constructed, checks this for the value before prompting the user for input.
  # @param no_prompt [Boolean] The context being constructed, checks this for the value before prompting the user for input.
  # @param api_params [Hash] Optional map of parameters to include in API request for select option types
  # @return input value for the option type, usually a string or number if the value is an ID or of type: number
	def prompt_value(option_type, options, no_prompt=false, api_params={})
		# this does not work with fieldContext, so get rid of it
		return Morpheus::Cli::OptionTypes.prompt([option_type.merge({'fieldContext' => nil})], options, @api_client, api_params, no_prompt)[option_type['fieldName']]
	end
end