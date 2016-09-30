# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::VirtualImages
	include Morpheus::Cli::CliCommand

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
		if args.empty?
			puts "\nUsage: morpheus virtual-images [list,add, update,remove, details, lb-types]\n\n"
			return 
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'update'
				# update(args[1..-1])	
			when 'details'
				details(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'virtual-image-types'
				virtual_image_types(args[1..-1])
			else
				puts "\nUsage: morpheus virtual-images [list,add, update,remove, details, lb-types]\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus virtual-images list [-s] [-o] [-m] [-t]"
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
			build_common_options(opts, options, [:list, :json, :remote])
		end
		optparse.parse(args)
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
				end
				print reset,"\n\n"
			end
			
			
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def details(args)
				image_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus virtual-images details [name]"
			build_common_options(opts, options, [:json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)
		begin
			lb = find_lb_by_name(image_name)

			exit 1 if lb.nil?
			lb_type = find_lb_type_by_name(lb['type']['name'])
			if options[:json]
					puts JSON.pretty_generate({task:task})
			else
				print "\n", cyan, "Lb #{lb['name']} - #{lb['type']['name']}\n\n"
				lb_type['optionTypes'].sort { |x,y| x['displayOrder'].to_i <=> y['displayOrder'].to_i }.each do |optionType|
					puts "  #{optionType['fieldLabel']} : " + (optionType['type'] == 'password' ? "#{task['taskOptions'][optionType['fieldName']] ? '************' : ''}" : "#{task['taskOptions'][optionType['fieldName']] || optionType['defaultValue']}")
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			print_rest_exception(e, options)
			exit 1
		end
	end

	def update(args)
		image_name = args[0]
		options = {}
		account_name = nil
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus tasks update [task] [options]"
			build_common_options(opts, options, [:options, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)

		connect(options)
		
		begin


			task = find_task_by_name_or_code_or_id(image_name)
			exit 1 if task.nil?
			lb_type = find_lb_type_by_name(task['type']['name'])

			#params = Morpheus::Cli::OptionTypes.prompt(add_user_option_types, options[:options], @api_client, options[:params]) # options[:params] is mysterious
			params = options[:options] || {}

			if params.empty?
				puts "\n#{optparse.banner}\n\n"
				option_lines = update_task_option_types(lb_type).collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
				puts "\nAvailable Options:\n#{option_lines}\n\n"
				exit 1
			end

			#puts "parsed params is : #{params.inspect}"
			task_keys = ['name']
			changes_payload = (params.select {|k,v| task_keys.include?(k) })
			task_payload = task
			if changes_payload
				task_payload.merge!(changes_payload)
			end
			puts params
			if params['taskOptions']
				task_payload['taskOptions'].merge!(params['taskOptions'])
			end

			request_payload = {task: task_payload}
			response = @virtual_images_interface.update(task['id'], request_payload)
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


	def virtual_image_types(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus virtual-images lb-types"
			build_common_options(opts, options, [:json, :remote])
		end
		optparse.parse(args)
		connect(options)
		begin
			json_response = @virtual_images_interface.load_balancer_types()
			if options[:json]
					print JSON.pretty_generate(json_response)
			else
				lb_types = json_response['virtualImageTypes']
				print "\n" ,cyan, bold, "Morpheus Virtual Image Types\n","============================", reset, "\n\n"
				if lb_types.nil? || lb_types.empty?
					puts yellow,"No image types currently exist on this appliance. This could be a seed issue.",reset
				else
					print cyan
					lb_table_data = lb_types.collect do |lb_type|
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

	def add(args)
		image_name = args[0]
		lb_type_name = nil
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus virtual-images add [lb] -t LB_TYPE"
			opts.on( '-t', '--type LB_TYPE', "Lb Type" ) do |val|
				lb_type_name = val
			end
			build_common_options(opts, options, [:options, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
		connect(options)

		if lb_type_name.nil?
			puts "LB Type must be specified...\n#{optparse.banner}"
			exit 1
		end

		lb_type = find_lb_type_by_name(lb_type_name)
		if lb_type.nil?
			puts "LB Type not found!"
			exit 1
		end
		input_options = Morpheus::Cli::OptionTypes.prompt(lb_type['optionTypes'],options[:options],@api_client, options[:params])
		payload = {task: {name: image_name, taskOptions: input_options['taskOptions'], type: {code: lb_type['code'], id: lb_type['id']}}}
		begin
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
		image_name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = "Usage: morpheus virtual-images remove [name]"
			build_common_options(opts, options, [:auto_confirm, :json, :remote])
		end
		if args.count < 1
			puts "\n#{optparse.banner}\n\n"
			exit 1
		end
		optparse.parse(args)
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

end
