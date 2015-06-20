require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'



class Morpheus::Cli::Remote
	include Term::ANSIColor
	def initialize() 
		@appliances = load_appliance_file
	end

	def handle(args) 
		if args.empty?
			puts "Usage: morpheus remote [list,add,remove,use] [name] [host]"
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'add'
				add(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			when 'use'
				use(args[1..-1])
		end
	end

	def list(args)
		print "\n" ,blue, bold, "Morpheus Appliances\n","==================", reset, "\n\n"
		# print red, bold, "red bold", reset, "\n"
		if @appliances == nil || @appliances.empty?
		else
		end
		@appliances.each do |app_name, v| 
			print blue
			if v[:active] == true
				print bold, "=> #{app_name}\t#{v[:host]}",reset,"\n"
			else
				print "=  #{app_name}\t#{v[:host]}",reset,"\n"
			end
		end
		print "\n\n# => - current\n\n"
	end

	def add(args)
	end

	def remove(args)
		if args.empty?
			puts "Usage: morpheus remote remove [name]"
		end
		name = args[0].to_sym
		if @appliances[name] == nil
			print red, "Remote appliance not configured for #{args[0]}", reset, "\n"
		else
			active = false
			if @appliances[name][:active]
				active = true
			end
			@appliances.delete(name)
			if active && @!appliances.empty?
				@appliances[@appliances.keys.first][:active] = true
			end
		end
		save_appliances(@appliances)
	end

	def use(args)
		if args.empty?
			puts "Usage: morpheus remote use [name]"
		end
		name = args[0].to_sym
		if @appliances[name] == nil
			print red, "Remote appliance not configured for #{args[0]}", reset, "\n"
		else
			@appliances.each do |k,v|
				if k == name
					v[:active] = true
				else
					v[:active] = false
				end
			end
		end
		save_appliances(@appliances)
	end

	# Provides the current active appliance url information
	def self.active_appliance
		if !defined?(@@appliance)
			@@appliance = load_appliance_file.select { |k,v| v[:active] == true}
		end
		return @@appliance
	end


private
	

	def self.load_appliance_file
		remote_file = appliances_file_path
		if File.exist? remote_file
			return YAML.load_file(remote_file)
		else
			return {
				morpheus: {
					host: 'https://api.gomorpheus.com',
					active: true
				}
			}
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
	end
end