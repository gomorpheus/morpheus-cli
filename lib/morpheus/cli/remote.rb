require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'


class Morpheus::Cli::Remote
	include Morpheus::Cli::CliCommand

	register_subcommands :list, :add, :update, :remove, :use, :unuse, :current => :print_current

	def initialize() 
		@appliances = ::Morpheus::Cli::Remote.load_appliance_file
		# @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
		#connect()
	end

	# def connect(opts)
	#   @api_client = establish_remote_appliance_connection(opts)
	# end

	def handle(args)
		if args.count == 0
			list(args)
		else
			handle_subcommand(args)
		end
	end

	def list(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			build_common_options(opts, options, [])
		end
		optparse.parse!(args)

		print "\n" ,cyan, bold, "Morpheus Appliances\n","==================", reset, "\n\n"
		# print red, bold, "red bold", reset, "\n"
		if @appliances == nil || @appliances.empty?
			puts yellow,"No remote appliances configured. Use `remote add`",reset
		else
			rows = @appliances.collect do |app_name, v|
				{
					active: (v[:active] ? "=>" : ""), 
					name: app_name, 
					host: v[:host]
				}
			end
			print cyan
			tp rows, {:active => {:display_name => ""}}, {:name => {:width => 16}}, {:host => {:width => 40}}
			print reset
			# if @@appliance
			active_appliance_name, active_appliance_host = Morpheus::Cli::Remote.active_appliance
			if active_appliance_name
				print cyan, "\n# => - current\n\n", reset
			else
				print yellow, "\n# => no current remote appliance\n\n", reset
			end
		end
	end

	def add(args)
		options = {}
		use_it = false
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] [host] [--use]")
			build_common_options(opts, options, [])
			opts.on( '--use', '--use', "Make this the current remote appliance" ) do
				use_it = true
			end
			# let's free up the -d switch for global options, maybe?
			opts.on( '-d', '--default', "Does the same thing as --use" ) do
				use_it = true
			end
		end
		optparse.parse!(args)
		if args.count < 2
			puts optparse
			exit 1
		end

		name = args[0].to_sym

		if @appliances[name] != nil
			print red, "Remote appliance already configured for #{args[0]}", reset, "\n"
		else
			@appliances[name] = {
				host: args[1],
				active: use_it
			}
			if use_it
				set_active_appliance name
				# save_appliances(@appliances)
			else
				::Morpheus::Cli::Remote.save_appliances(@appliances)
			end
		end
		list([])
	end

	def remove(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name]")
			build_common_options(opts, options, [])
			opts.on( '-d', '--default', "Make this the default remote appliance" ) do
				options[:default] = true
			end
		end
		optparse.parse!(args)
		if args.empty?
			puts optparse
			exit 1
		end
				name = args[0].to_sym
		if @appliances[name] == nil
			print red, "Remote appliance not found by the name '#{args[0]}'", reset, "\n"
		else
			active = false
			if @appliances[name][:active]
				active = true
			end
			@appliances.delete(name)
			if active && !@appliances.empty?
				@appliances[@appliances.keys.first][:active] = true
			end
			::Morpheus::Cli::Remote.save_appliances(@appliances)
			list([])
		end
	end

	def use(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage("[name] [--none]")
			opts.on('--none','--none', "Do not use any appliance. This will prevent you from executing commands unless --remote is used.") do |val|
				options[:unuse] = true
			end
			build_common_options(opts, options, [])
		end
		optparse.parse!(args)

		if options[:unuse]
			set_active_appliance nil # clear
			unless options[:quiet]
				print dark
				puts "Switched to no active appliance."
				puts "This will prevent you from executing commands unless --remote is used."
				print reset
			end
			return # exit 0
		end
				if args.count == 0
			puts optparse
			exit 1
		end

		new_appliance_name = args[0].to_sym
		active_appliance_name, active_appliance_host = Morpheus::Cli::Remote.active_appliance
		# if @@appliance && (@@appliance[:name].to_s == new_appliance_name.to_s)
		if active_appliance_name && active_appliance_name.to_s == new_appliance_name.to_s
			print reset,"Already using the appliance '#{args[0]}'","\n",reset
		else
			if @appliances[new_appliance_name] == nil
				print red, "Remote appliance not found by the name '#{args[0]}'", reset, "\n"
			else
				@@appliance = nil # clear cached active appliance
				set_active_appliance(new_appliance_name)
				#print cyan,"Switched to using appliance #{args[0]}","\n",reset
				#list([])
			end
		end

	end

	def unuse(args)
		use(args + ['--none'])
	end

	def print_current(args)
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = subcommand_usage()
			build_common_options(opts, options, [])
		end
		optparse.parse!(args)

		active_appliance_name, active_appliance_host = Morpheus::Cli::Remote.active_appliance
		if active_appliance_name
			print cyan,active_appliance_name,"\n",reset
		else
			print dark,"No active appliance. See `remote use`","\n",reset
		end
	end

	def set_active_appliance(name)
		@@appliance = nil # clear cached active appliance
		@appliances.each do |k,v|
			is_match = (name ? (k == name.to_sym) : false)
			if is_match
				v[:active] = true
				# @@appliance = v
			else
				v[:active] = false
			end
		end
		::Morpheus::Cli::Remote.save_appliances(@appliances)
	end

	# Provides the current active appliance name, url
	def self.active_appliance
		if !defined?(@@appliance) || @@appliance.nil?
			@@appliance = load_appliance_file.select { |k,v| v[:active] == true}
		end
		# return @@appliance.keys[0], @@appliance[@@appliance.keys[0]][:host]
		# wtf!
		if !@@appliance.keys[0]
			return nil, nil
		end
		begin
			return @@appliance.keys[0], @@appliance[@@appliance.keys[0]][:host]
		rescue
			return nil, nil
		end
	end

	
	def self.load_appliance_file
		remote_file = appliances_file_path
		if File.exist? remote_file
			return YAML.load_file(remote_file)
		else
			return {}
			# return {
			# 	morpheus: {
			# 		host: 'https://api.gomorpheus.com',
			# 		active: true
			# 	}
			# }
		end
	end

	def self.appliances_file_path
		home_dir = Dir.home
		morpheus_dir = File.join(home_dir,".morpheus")
		if !Dir.exist?(morpheus_dir)
			Dir.mkdir(morpheus_dir)
		end
		return File.join(morpheus_dir,"appliances")
	end

	def self.save_appliances(appliance_map)
		File.open(appliances_file_path, 'w') {|f| f.write appliance_map.to_yaml } #Store
		@appliances = appliance_map
		@appliances
	end

	#  wtf, but then could just do Morpheus::Cli.Remote.connect(options)
	def self.connect(options={})
		newobj = self.new
		establish_remote_appliance_connection(options)
		return newobj
	end

end
