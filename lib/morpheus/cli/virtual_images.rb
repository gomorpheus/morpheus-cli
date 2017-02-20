# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

# JD: I don't think a lot of this has ever worked, fix it up.

class Morpheus::Cli::VirtualImages
	include Morpheus::Cli::CliCommand

	register_subcommands :list, :get, :add, :update, :types => :virtual_image_types
	alias_subcommand :details, :get

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
		@virtual_images_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).virtual_images
		
		if @access_token.empty?
			print_red_alert "Invalid Credentials. Unable to acquire access token. Please verify your credentials and try again."
			exit 1
		end
	end

	def handle(args)
		handle_subcommand(args)
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			opts.on( '-t', '--type IMAGE_TYPE', "Image Type" ) do |val|
				options[:imageType] = val.downcase
			end

			opts.on( '', '--all', "All Images" ) do |val|
				options[:filterType] = 'All'
			end
			opts.on( '', '--user', "User Images" ) do |val|
				options[:filterType] = 'User'
			end
			opts.on( '', '--system', "System Images" ) do |val|
				options[:filterType] = 'System'
			end
			build_common_options(opts, options, [:list, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		connect(options)
		begin
			params = {}
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end
			if options[:imageType]
				params[:imageType] = options[:imageType]
			end
			if options[:filterType]
				params[:filterType] = options[:filterType]
			end
			if options[:dry_run]
				print_dry_run @virtual_images_interface.dry.get(params)
				return
			end
			json_response = @virtual_images_interface.get(params)
			if options[:json]
				print JSON.pretty_generate(json_response)
			else
				images = json_response['virtualImages']
				print "\n" ,cyan, bold, "Morpheus Virtual Images\n","=======================", reset, "\n\n"
				if images.empty?
					puts yellow,"No virtual images currently exist.",reset
				else
					print cyan
					image_table_data = images.collect do |image|
						{name: image['name'], id: image['id'], type: image['imageType'].upcase, source: image['userUploaded'] ? "#{green}UPLOADED#{cyan}" : (image['systemImage'] ? 'SYSTEM' : "#{white}SYNCED#{cyan}"), storage: !image['storageProvider'].nil? ? image['storageProvider']['name'] : 'Default', size: image['rawSize'].nil? ? 'Unknown' : "#{Filesize.from("#{image['rawSize']} B").pretty}"}
					end
					tp image_table_data, :id, :name, :type, :storage, :size, :source
					print_results_pagination(json_response)
				end
				print reset,"\n"
			end
			
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def get(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		image_name = args[0]
		connect(options)
		begin
			if options[:dry_run]
				print_dry_run @virtual_images_interface.dry.get({name: image_name})
				return
			end
			image = find_image_by_name(image_name)
			exit 1 if image.nil?

			if options[:json]
				puts JSON.pretty_generate({virtualImage: image})
			else
				print "\n" ,cyan, bold, "Virtual Image Details\n","==================", reset, "\n\n"
				print cyan
				puts "ID: #{image['id']}"
				puts "Name: #{image['name']}"
				puts "Type: #{image['imageType']}"
				puts "Date Created: #{format_local_dt(image['dateCreated'])}"
				#puts "Last Updated: #{format_local_dt(image['lastUpdated'])}"
				print reset,"\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	# JD: I don't think this has ever worked
	def update(args)
		image_name = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] [options]")
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		if args.count < 1
			puts optparse
			exit 1
		end
		optparse.parse!(args)

		connect(options)
		
		begin

			image = find_image_by_name(image_name)
			exit 1 if image.nil?

			params = options[:options] || {}

			if params.empty?
				puts optparse
				option_lines = update_virtual_image_option_types().collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			image_payload = {id: image['id']}
			image_payload.merge(params)
			# JD: what can be updated?
			payload = {virtualImage: image_payload}
			if options[:dry_run]
				print_dry_run @virtual_images_interface.dry.update(image['id'], payload)
				return
			end
			response = @virtual_images_interface.update(image['id'], payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
				if !response['success']
					exit 1
				end
			else
				print "\n", cyan, "Task #{response['task']['name']} updated", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	# JD: this endpoint does not exist??
	def virtual_image_types(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			build_common_options(opts, options, [:json, :dry_run, :remote])
		end
		optparse.parse!(args)
		connect(options)
		begin
			params = {}
			if options[:dry_run]
				print_dry_run @virtual_images_interface.dry.virtual_image_types(params)
				return
			end
			json_response = @virtual_images_interface.virtual_image_types(params)
			if options[:json]
				print JSON.pretty_generate(json_response)
			else
				image_types = json_response['virtualImageTypes']
				print "\n" ,cyan, bold, "Morpheus Virtual Image Types\n","============================", reset, "\n\n"
				if image_types.nil? || image_types.empty?
					puts yellow,"No image types currently exist on this appliance. This could be a seed issue.",reset
				else
					print cyan
					lb_table_data = image_types.collect do |lb_type|
						{name: lb_type['name'], id: lb_type['id'], code: lb_type['code']}
					end
					tp lb_table_data, :id, :name, :code
				end

				print reset,"\n\n"
			end
			
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	# JD: I don't think this has ever worked
	def add(args)
		image_type_name = nil
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] -t TYPE")
			opts.banner = "Usage: morpheus virtual-images add [name] -t TYPE"
			opts.on( '-t', '--type TYPE', "Virtual Image Type" ) do |val|
				image_type_name = val
			end
			build_common_options(opts, options, [:options, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		image_name = args[0]
		connect(options)

		if image_type_name.nil?
			puts "Virtual Image Type must be specified"
			puts optparse
			exit 1
		end

		image_type = find_image_type_by_name(image_type_name)
		exit 1 if image_type.nil?

		input_options = Morpheus::Cli::OptionTypes.prompt(lb_type['optionTypes'],options[:options],@api_client, options[:params])
		payload = {task: {name: image_name, taskOptions: input_options['taskOptions'], type: {code: lb_type['code'], id: lb_type['id']}}}
		begin
			if options[:dry_run]
				print_dry_run @virtual_images_interface.dry.create(payload)
				return
			end
			json_response = @virtual_images_interface.create(payload)
			if options[:json]
				print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "LB #{json_response['virtualImage']['name']} created successfully", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def remove(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
		end
		optparse.parse!(args)
		if args.count < 1
			puts optparse
			exit 1
		end
		image_name = args[0]
		connect(options)
		begin
			image = find_image_by_name(image_name)
			exit 1 if image.nil?
			unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the virtual image #{image['name']}?")
				exit
			end
			json_response = @virtual_images_interface.destroy(image['id'])
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				print "\n", cyan, "Virtual Image #{image['name']} removed", reset, "\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end


private
	def find_image_by_name(val)
		raise "find_image_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @virtual_images_interface.get(val)
		result = nil
		if !results['virtualImages'].nil? && !results['virtualImages'].empty?
			result = results['virtualImages'][0]
		elsif val.to_i.to_s == val
			results = @virtual_images_interface.get(val.to_i)
			result = results['virtualImage']
		end
		if result.nil?
			print red,bold, "\nVirtual Image not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

	def find_image_type_by_name(val)
		raise "find_,age_type_by_name passed a bad name: #{val.inspect}" if val.to_s == ''
		results = @virtual_images_interface.virtual_image_types(val)
		result = nil
		if !results['virtualImageTypes'].nil? && !results['virtualImageTypes'].empty?
			result = results['virtualImageTypes'][0]
		elsif val.to_i.to_s == val
			results = @virtual_images_interface.virtual_image_types(val.to_i)
			result = results['virtualImageType']
		end
		if result.nil?
			print red,bold, "\nImage Type not found by '#{val}'\n\n",reset
			return nil
		end
		return result
	end

	# JD: todo filename, etc...
	def add_virtual_image_option_types
		[
			{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 0}
		]
	end

	# JD: what can be updated?
	def update_virtual_image_option_types
		[]
	end

end
