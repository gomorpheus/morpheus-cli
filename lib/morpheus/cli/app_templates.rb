# require 'yaml'
require 'io/console'
require 'rest_client'
require 'term/ansicolor'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::AppTemplates
	include Term::ANSIColor
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  
	def initialize() 
		@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
	end

	def connect(opts)
		@access_token = Morpheus::Cli::Credentials.new(@appliance_name,@appliance_url).request_credentials()
		if @access_token.empty?
			print red,bold, "\nInvalid Credentials. Unable to acquire access token. Please verify your credentials and try again.\n\n",reset
			exit 1
		end
		@active_groups = ::Morpheus::Cli::Groups.load_group_file
		@api_client = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url)
		@app_templates_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).app_templates
	end

	def handle(args)
		usage = "Usage: morpheus app-templates [list,details,add,update,remove] [name]"
		if args.empty?
			puts "\n#{usage}\n\n"
			exit 1
		end

		case args[0]
			when 'list'
				list(args[1..-1])
			when 'details'
				details(args[1..-1])
			# when 'add'
			# 	add(args[1..-1])
			# when 'update'
			# 	update(args[1..-1])
			when 'remove'
				remove(args[1..-1])
			else
				puts "\n#{usage}\n\n"
				exit 127
		end
	end

	def list(args)
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			[:phrase, :offset, :max, :sort, :direction].each do |k|
				params[k] = options[k] unless options[k].nil?
			end

			json_response = @app_templates_interface.list(params)
			app_templates = json_response['appTypes']
			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "Morpheus App Templates\n","==================", reset, "\n\n"
				if app_templates.empty?
					puts yellow,"No app templates found.",reset
				else
					print_app_templates_table(app_templates)
				end
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def details(args)
		usage = "Usage: morpheus app-templates details [name]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		options = {}
		params = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage

			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
	
			app_template = find_app_template_by_name(name)
			exit 1 if app_template.nil?

			json_response = @app_templates_interface.get(app_template['id'])
			app_template = json_response['appType']

			if options[:json]
				print JSON.pretty_generate(json_response)
				print "\n"
			else
				print "\n" ,cyan, bold, "App Template Details\n","==================", reset, "\n\n"
				print cyan
				puts "ID: #{app_template['id']}"
				puts "Name: #{app_template['name']}"
				#puts "Category: #{app_template['category']}"
				instance_type_names = (app_template['instanceTypes'] || []).collect {|it| it['name'] }
				puts "Instance Types: #{instance_type_names.join(', ')}"
				puts "Account: #{app_template['account'] ? app_template['account']['name'] : ''}"
				puts "Config: #{app_template['config']}"
				print reset,"\n\n"
			end
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

	def add(args)
		print_red_alert "NOT YET IMPLEMENTED"
		exit 1
	end

	def update(args)
		print_red_alert "NOT YET IMPLEMENTED"
		exit 1
	end

	def remove(args)
		usage = "Usage: morpheus app-templates remove [name]"
		if args.count < 1
			puts "\n#{usage}\n\n"
			exit 1
		end
		name = args[0]
		options = {}
		optparse = OptionParser.new do|opts|
			opts.banner = usage
			Morpheus::Cli::CliCommand.genericOptions(opts,options)
		end
		optparse.parse(args)
		connect(options)
		begin
			# allow finding by ID since name is not unique!
			app_template = ((name.to_s =~ /\A\d{1,}\Z/) ? find_app_template_by_id(name) : find_app_template_by_name(name) )
			exit 1 if app_template.nil?
			exit unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the app template #{app_template['name']}?")
			@app_templates_interface.destroy(app_template['id'])
			# list([])
			print "\n", cyan, "App Template #{app_template['name']} removed", reset, "\n\n"
		rescue RestClient::Exception => e
			::Morpheus::Cli::ErrorHandler.new.print_rest_exception(e)
			exit 1
		end
	end

private
	

	def add_app_template_option_types
		[
			{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
			# todo...
		]
	end

	def update_app_template_option_types
		add_app_template_option_types
	end

	def find_app_template_by_id(id)
    begin
      json_response = @app_templates_interface.get(id.to_i)
      return json_response['appType']
    rescue RestClient::Exception => e
      if e.response.code == 404
        print_red_alert "App Template not found by id #{id}"
      else
        raise e
      end
    end
  end

	def find_app_template_by_name(name)
    app_templates = @app_templates_interface.list({name: name.to_s})['appTypes']
    if app_templates.empty?
      print_red_alert "App Template not found by name #{name}"
      return nil
    elsif app_templates.size > 1
      print_red_alert "#{app_templates.size} app templates by name #{name}"
      print_app_templates_table(app_templates, {color: red})
      print reset,"\n\n"
      return nil
    else
      return app_templates[0]
    end
  end

	def print_app_templates_table(app_templates, opts={})
    table_color = opts[:color] || cyan
    rows = app_templates.collect do |app_template|
    	instance_type_names = (app_template['instanceTypes'] || []).collect {|it| it['name'] }.join(', ')
      {
        id: app_template['id'], 
        name: app_template['name'], 
        #code: app_template['code'], 
        instance_types: instance_type_names,
        account: app_template['account'] ? app_template['account']['name'] : nil, 
        #dateCreated: format_local_dt(app_template['dateCreated']) 
      }
    end
    
    print table_color
    tp rows, [
      :id, 
      :name, 
      {:instance_types => {:display_name => "Instance Types"} },
      :account, 
      #{:dateCreated => {:display_name => "Date Created"} }
    ]
    print reset
  end

end
