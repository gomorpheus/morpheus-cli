# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/whoami_helper'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Whoami
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::WhoamiHelper
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :whoami

  # no subcommands, just show()

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    #@api_client = establish_remote_appliance_connection(opts)
    # begin
      @api_client = establish_remote_appliance_connection(opts.merge({:no_prompt => true, :skip_verify_access_token => true}))
      @groups_interface = @api_client.groups
      @active_group_id = Morpheus::Cli::Groups.active_group
    # rescue Morpheus::Cli::CommandError => err
    #   puts_error err
    # end
  end

  def handle(args)
    show(args)
  end

  def show(args)
    options = {}
    params = {}
    username_only = false
    access_token_only = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on( '-n', '--name', "Print only your username." ) do
        username_only = true
      end
      opts.on('-f','--feature-access', "Display Feature Access") do
        options[:include_feature_access] = true
      end
      # these are things that morpheus users get has to display...
      # opts.on(nil,'--group-access', "Display Group Access") do
      #   options[:include_group_access] = true
      # end
      # opts.on(nil,'--cloud-access', "Display Cloud Access") do
      #   options[:include_cloud_access] = true
      # end
      # opts.on(nil,'--instance-type-access', "Display Instance Type Access") do
      #   options[:include_instance_type_access] = true
      # end
      # opts.on('-a','--all-access', "Display All Access Lists") do
      #   options[:include_feature_access] = true
      #   options[:include_group_access] = true
      #   options[:include_cloud_access] = true
      #   options[:include_instance_type_access] = true
      # end
      opts.on('-t','--token-only', "Print your access token only") do
        access_token_only = true
      end
      build_common_options(opts, options, [:json, :remote, :dry_run, :quiet])
    end
    optparse.parse!(args)
    connect(options)
    begin
      # check to see if they have credentials instead of just trying to connect (and prompting)

      if !@appliance_name
        # never gets here..
        #raise_command_error "Please specify a Morpheus Appliance with -r or see the command `remote use`"
        print yellow,"Please specify a Morpheus Appliance with -r or see `remote use`.#{reset}\n"
        return 1
      end
      
      if options[:dry_run]
        print_dry_run @api_client.whoami.setopts(options).dry.get(params)
        return 0
      end

      # todo: fix potential issue here, should be able to use --remote-url or --username
      # in which case you do not have to be logged in (saved credentials)...
      # maybe just update connect() to do @api_client = establish_remote_appliance_connection(opts)
      # wallet = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).request_credentials(options)
      wallet = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
      token = wallet ? wallet['access_token'] : nil
      if !token
        if options[:quiet]
          return 1
        elsif access_token_only
          puts_error "(logged out)" # stderr probably
          return 1
        else
          print yellow,"You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
          print yellow,"Use the 'login' command.",reset,"\n"
          return 1
        end
      end

      #json_response = load_whoami()

      whoami_interface = @api_client.whoami.setopts(options)
      whoami_response = whoami_interface.get()
      json_response = whoami_response
      @current_user = whoami_response["user"]
      if @current_user.empty?
        print_red_alert "Unauthenticated. Please login."
        exit 1
      end
      @is_master_account = whoami_response["isMasterAccount"]
      @user_permissions = whoami_response["permissions"]

      if whoami_response["appliance"]
        @appliance_build_verison = whoami_response["appliance"]["buildVersion"]
      else
        @appliance_build_verison = nil
      end

      if access_token_only
        if options[:quiet]
          return @current_user ? 0 : 1
        end
        if @access_token.nil?
          print yellow,"\n","No access token. Please login",reset,"\n"
          return false
        end
        print cyan,@access_token.to_s,reset,"\n"
        return 0
      end

      if username_only
        if options[:quiet]
          return @current_user ? 0 : 1
        end
        if @current_user.nil?
          puts_error "(logged out)" # "(anonymous)" || ""
          return 1
        else
          print cyan,@current_user['username'].to_s,reset,"\n"
          return 0
        end
      end

      
      active_group = nil
      begin
        active_group = @active_group_id ? find_group_by_name_or_id(@active_group_id) : nil # via InfrastructureHelper mixin
      rescue => err
        if options[:debug]
          print red,"Unable to determine active group: #{err}\n",reset
        end
      end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        if @current_user.nil?
          print yellow,"\n","No active session. Please login",reset,"\n"
          exit 1
        end

        print_h1 "Current User", options
        print cyan
        print_description_list({
          "ID" => 'id',
          "Account" => lambda {|it| (it['account'] ? it['account']['name'] : '') + (@is_master_account ? " (Master Account)" : '') },
          # "First Name" => 'firstName',
          # "Last Name" => 'lastName',
          # "Name" => 'displayName',
          "Name" => lambda {|it| it['firstName'] ? it['displayName'] : '' },
          "Username" => 'username',
          "Email" => 'email',
          "Role" => lambda {|it| format_user_role_names(it) }
        }, @current_user)
        print cyan

        if options[:include_feature_access]
          if @user_permissions
            print_h2 "Feature Permissions", options
            print cyan
            rows = @user_permissions.collect do |code, access|
              {code: code, access: get_access_string(access) }
            end
            print as_pretty_table(rows, [:code, :access], options)
          else
            puts yellow,"No permissions found.",reset
          end
        end

        print_h1 "Remote Appliance", options
        print cyan
        appliance_data = {
          'name' => @appliance_name,
          'url' => @appliance_url,
          'buildVersion' => @appliance_build_verison
        }
        print_description_list({
          "Name" => 'name',
          "URL" => 'url',
          "Version" => 'buildVersion'
        }, appliance_data)

        if active_group
          print cyan
          # print_h1 "Active Group", options
          # print cyan
          # print_description_list({
          #   "ID" => 'id',
          #   "Name" => 'name'
          # }, active_group)
          print cyan, "\n# => Currently using group #{active_group['name']}\n", reset
          print reset,"\n"
        else
          print "\n", reset
          print "No active group. See `groups use`\n",reset
          print reset,"\n"
        end

        # save pertinent session info to the appliance
        begin
          now = Time.now.to_i
          app_map = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
          app_map[:username] = @current_user['username']
          app_map[:authenticated] = true
          app_map[:status] = 'ready'
          app_map[:build_version] = @appliance_build_verison if @appliance_build_verison
          app_map[:last_success_at] = now
          ::Morpheus::Cli::Remote.save_remote(@appliance_name, app_map)
        rescue => err
          puts "failed to save remote appliance info"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      # if e.response && e.response.code == 401
      #   puts "It looks like you need to login to the remote appliance [#{@appliance_name}] #{@appliance_url}"
      #   if Morpheus::Cli::OptionTypes.confirm("Would you like to login now?")
      #     return Morpheus::Cli::Login.new.login([])
      #   end
      # end
      return 1
    end
  end

end
