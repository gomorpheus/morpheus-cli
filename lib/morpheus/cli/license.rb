# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::License
	include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance	
	end

	def connect(opts)
		if opts[:remote]
			@appliance_url = opts[:remote]
			@appliance_name = opts[:remote]
			@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials(opts)
		else
			@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials(opts)
		end
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)		
		@license_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).license
		
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
	end


	def handle(args) 
		if args.empty?
			puts "\nUsage: morpheus license [details, apply]\n\n"
			return 
		end

		case args[0]
			when 'apply'
				apply(args[1..-1])	
			when 'details'
				details(args[1..-1])
			else
				puts "\nUsage: morpheus license [details, apply]\n\n"
				exit 127
		end
	end


	def details(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus license details"
			build_common_options(opts, options, [:json, :remote])
		end
		optparse.parse(args)
		connect(options)
		begin
			license = @license_interface.get()
			
			if options[:json]
					puts JSON.pretty_generate(license)
			else
				if license['license'].nil?
					puts "No License Currently Applied to the appliance."
					exit 1
				else
					print "\n", cyan, "License\n=======\n"
					max_memory = Filesize.from("#{license['license']['maxMemory']} B").pretty
					max_storage = Filesize.from("#{license['license']['maxStorage']} B").pretty
					used_memory = Filesize.from("#{license['usedMemory']} B").pretty
					puts "Account: #{license['license']['accountName']}"
					puts "Start Date: #{license['license']['startDate']}"
					puts "End Date: #{license['license']['endDate']}"
					puts "Memory: #{used_memory} / #{max_memory}"
					puts "Max Storage: #{max_storage}"
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def apply(args)
		key = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus license apply [key]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)

		connect(options)
		
		begin
			license_results = @license_interface.apply(key)

			if options[:json]
					puts JSON.pretty_generate(license_results)
			else
				puts "License applied successfully!"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

end
