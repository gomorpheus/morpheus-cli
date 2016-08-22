require 'yaml'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'json'


class Morpheus::Cli::ErrorHandler
	include Term::ANSIColor

	def print_errors(response, options = {})
		if options[:json]
			print JSON.pretty_generate(response)
		else
			if !response['success']
				print red,bold, "\n"
				if response['msg']
					puts response['msg']
				end
				if response['errors']
					response['errors'].each do |key, value|
						print "* #{key}: #{value}\n"
					end
				end
				print reset, "\n"
			end
		end
	end
end