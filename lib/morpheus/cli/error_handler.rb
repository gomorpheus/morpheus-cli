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

	def print_rest_exception(e, options={})
		if e.response.code == 400
			json_response = JSON.parse(e.response.to_s)
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				::Morpheus::Cli::ErrorHandler.new.print_errors(json_response)
			end
		else
			puts "Error Communicating with the Appliance. Please try again later. #{e}"
		end
		print reset
	end

end
