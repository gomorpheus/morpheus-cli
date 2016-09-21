# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::InstanceTypes
  include Morpheus::Cli::CliCommand
	include Term::ANSIColor
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		@groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
	end


	def handle(args) 
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			return 1
		end
		if args.empty?
			puts "\nUsage: morpheus instance-types [list,details] [name]\n\n"
			return
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'details'
				details(args[1..-1])
			else
				puts "\nUsage: morpheus instance-types [list,details] [name]\n\n"
		end
	end


	def details(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus instance-type details [name]"
			build_common_options(opts, options, [:json])
		end
		optparse.parse(args)
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			return
		end
		name = args[0]
		begin
			json_response = @instance_types_interface.get({name: name})

			if options[:json]
				print JSON.pretty_generate(json_response), "\n" and return
			end

			instance_type = json_response['instanceTypes'][0]

			if instance_type.nil?
				puts yellow,"No instance type found by name #{name}.",reset
			else
				print "\n" ,cyan, bold, "Instance Type Details\n","==================", reset, "\n\n"
				versions = instance_type['versions'].join(', ')
				print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
				instance_type['instanceTypeLayouts'].each do |layout|
					print green, "     - #{layout['name']}\n",reset
				end
				print reset,"\n\n"
			end

		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e, options)
			exit 1
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			build_common_options(opts, options, [:list, :json])
		end
		optparse.parse(args)
		begin
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @instance_types_interface.get(params)

			if options[:json]
				print JSON.pretty_generate(json_response), "\n" and return
			end

			instance_types = json_response['instanceTypes']
			print "\n" ,cyan, bold, "Morpheus Instance Types\n","==================", reset, "\n\n"
			if instance_types.empty?
				puts yellow,"No instance types currently configured.",reset
			else
				instance_types.each do |instance_type|
					versions = instance_type['versions'].join(', ')
					print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
					instance_type['instanceTypeLayouts'].each do |layout|
						print green, "     - #{layout['name']}\n",reset
					end
				end
			end
			print reset,"\n\n"
			
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e, options)
			exit 1
		end
	end
end
