require 'io/console'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::InstanceTypes
  include Morpheus::Cli::CliCommand

	register_subcommands :list, :get
	alias_subcommand :details, :get

	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		@instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
	end

	def handle(args)
		handle_subcommand(args)
	end

	def get(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 
		end
		name = args[0]
		connect(options)
		begin
			if options[:dry_run]
				print_dry_run @instance_types_interface.dry.get({name: name})
				return
			end
			json_response = @instance_types_interface.get({name: name})

			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end

			instance_type = json_response['instanceTypes'][0]

			if instance_type.nil?
				puts yellow,"No instance type found by name #{name}.",reset
			else
				print "\n" ,cyan, bold, "Instance Type Details\n","==================", reset, "\n\n"
				versions = instance_type['versions'].join(', ')
				print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
				layout_names = instance_type['instanceTypeLayouts'].collect { |layout| layout['name'] }.uniq.sort
				layout_names.each do |layout_name|
					print green, "     - #{layout_name}\n",reset
				end
				# instance_type['instanceTypeLayouts'].each do |layout|
				# 	print green, "     - #{layout['name']}\n",reset
				# end
				print reset,"\n"
			end

		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			build_common_options(opts, options, [:list, :json, :dry_run])
		end
		optparse.parse!(args)
		connect(options)
		begin
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			if options[:dry_run]
				print_dry_run @instance_types_interface.dry.get(params)
				return
			end
			
			json_response = @instance_types_interface.get(params)

			if options[:json]
				print JSON.pretty_generate(json_response), "\n"
				return
			end

			instance_types = json_response['instanceTypes']
			print "\n" ,cyan, bold, "Morpheus Instance Types\n","==================", reset, "\n\n"
			if instance_types.empty?
				puts yellow,"No instance types currently configured.",reset
			else
				instance_types.each do |instance_type|
					versions = instance_type['versions'].join(', ')
					print cyan, "=  #{instance_type['name']} (#{instance_type['code']}) - #{versions}\n"
					layout_names = instance_type['instanceTypeLayouts'].collect { |layout| layout['name'] }.uniq.sort
					layout_names.each do |layout_name|
						print green, "     - #{layout_name}\n",reset
					end
					# instance_type['instanceTypeLayouts'].each do |layout|
					# 	print green, "     - #{layout['name']}\n",reset
					# end
					#print JSON.pretty_generate(instance_type['instanceTypeLayouts'].first), "\n"
				end

			end
			print reset,"\n"
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end
end
