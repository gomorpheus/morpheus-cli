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
    @api_client = establish_remote_appliance_connection(opts)
    @groups_interface = @api_client.groups
    @active_group_id = Morpheus::Cli::Groups.active_group
  end

  def handle(args)
    show(args)
  end

  def show(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = usage
      opts.on(nil,'--feature-access', "Display Feature Access") do |val|
        options[:include_feature_access] = true
      end
      # opts.on(nil,'--group-access', "Display Group Access") do
      #   options[:include_group_access] = true
      # end
      # opts.on(nil,'--cloud-access', "Display Cloud Access") do
      #   options[:include_cloud_access] = true
      # end
      # opts.on(nil,'--instance-type-access', "Display Instance Type Access") do
      #   options[:include_instance_type_access] = true
      # end
      opts.on(nil,'--all-access', "Display All Access Lists") do
        options[:include_feature_access] = true
        options[:include_group_access] = true
        options[:include_cloud_access] = true
        options[:include_instance_type_access] = true
      end
      build_common_options(opts, options, [:json, :remote, :dry_run]) # todo: support :remote too
    end
    optparse.parse!(args)
    # todo: check to see if they have credentials instead of just trying to connect (and prompting)
    connect(options)
    begin
      json_response = load_whoami()
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
        user = @current_user
        if !user
          puts yellow,"No active session. Please login",reset
          exit 1
        end

        # todo: impersonate command and show that info here

        print_h1 "Current User"
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
        }, user)
        print cyan

        if options[:include_feature_access]
          if @user_permissions
            print_h2 "Feature Permissions"
            print cyan
            rows = @user_permissions.collect do |code, access|
              {code: code, access: get_access_string(access) }
            end
            tp rows, [:code, :access]
          else
            puts yellow,"No permissions found.",reset
          end
        end

        print_h1 "Remote Appliance"
        print cyan
        appliance_data = {
          'name' => @appliance_name,
          'url' => @appliance_url,
          'buildVersion' => @appliance_build_verison
        }
        print_description_list({
          "Name" => 'name',
          "Url" => 'url',
          "Version" => 'buildVersion'
        }, appliance_data)

        if active_group
          print cyan
          # print_h1 "Active Group"
          # print cyan
          # print_description_list({
          #   "ID" => 'id',
          #   "Name" => 'name'
          # }, active_group)
          print cyan, "\n# => Currently using group #{active_group['name']}\n", reset
        else
          print "\n"
          print "No active group. See `groups use`\n",reset
        end

        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      if e.response && e.response.code == 401
        puts "It looks like you need to login to the remote appliance [#{@appliance_name}] #{@appliance_url}"
        if Morpheus::Cli::OptionTypes.confirm("Would you like to login now?")
          return Morpheus::Cli::Login.new.login([])
        end
      end
      exit 1
    end
  end


end
