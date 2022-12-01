require 'morpheus/cli/cli_command'

class Morpheus::Cli::Whoami
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::WhoamiHelper
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :whoami

  # no subcommands, just show()

  def connect(options)
    # @api_client = establish_remote_appliance_connection(options)
    @api_client = establish_remote_appliance_connection(options.merge({:skip_verify_access_token => true, :skip_login => true}))
    @whoami_interface = @api_client.whoami
  end

  def handle(args)
    get(args)
  end

  def get(args)
    options = {}
    params = {}
    username_only = false
    access_token_only = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on( '-n', '--name', "Print only your username." ) do
        username_only = true
      end
      opts.on('-a','--all', "Display All Details") do
        options[:include_feature_access] = true
        options[:include_group_access] = true
        options[:include_cloud_access] = true
        options[:include_instance_type_access] = true
      end
      opts.on('-p','--permissions', "Display Permissions") do
        options[:include_feature_access] = true
        # options[:include_group_access] = true
        # options[:include_cloud_access] = true
        # options[:include_instance_type_access] = true
      end
      # opts.on('-f','--feature-access', "Display Feature Access") do
      #   options[:include_feature_access] = true
      # end
      # opts.add_hidden_option('--feature-access')
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
      opts.on('-t','--token-only', "Print your access token only") do
        access_token_only = true
      end
      opts.on('--offline', '--offline', "Do this offline without an api request to refresh the remote appliance status.") do
        options[:do_offline] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
View information about the current user.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    begin
      if @access_token.nil?
        print_error yellow,"You are not currently logged in",reset,"\n"
        return 1, "no current user"
      end
      @whoami_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @whoami_interface.dry.get(params)
        return 0
      end

      #json_response = load_whoami()
      whoami_response = nil
      if options[:do_offline]
        # if @remote_appliance && @remote_appliance[:username]
        #   exit_code = 0
        # else
        #   exit_code = 1
        # end
        # no permissions, or even name stored atm, we should start storing that.
        # then we can start checking permissions nd restricting command visibility.
        whoami_response = {
          "user": {
            "username" => @remote_appliance ? @remote_appliance[:username] : nil
          },
          # "isMasterAccount" => true,
          "permissions" => [],
          "appliance" => {
           "buildVersion" => @remote_appliance ? @remote_appliance[:build_version] : nil
          }
        }
      else
        whoami_response = @whoami_interface.get(params)
      end
      json_response = whoami_response
      @current_user = whoami_response["user"]
      # if @current_user.nil?
      #   print_red_alert "Unauthenticated. Please login."
      #   exit 1
      # end
      @is_master_account = whoami_response["isMasterAccount"]
      @user_permissions = whoami_response["permissions"]

      if whoami_response["appliance"]
        @appliance_build_verison = whoami_response["appliance"]["buildVersion"]
      else
        @appliance_build_verison = nil
      end

      render_response(json_response, options) do

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

        if @current_user.nil?
          print yellow,"\n","No active session. Please login",reset,"\n"
          exit 1
        end
        subtitles = []
        #subtitles << "#{display_appliance(@appliance_name, @appliance_url)}"
        print_h1 "Current User", subtitles, options
        print cyan
        print_description_list({
          "ID" => 'id',
          "Username" => 'username',
          # "First Name" => 'firstName',
          # "Last Name" => 'lastName',
          # "Name" => 'displayName',
          "Name" => lambda {|it| "#{it['firstName']} #{it['lastName']}".strip },
          "Email" => 'email',
          "Tenant" => lambda {|it| (it['account'] ? it['account']['name'] : '') + (@is_master_account ? " (Master Tenant)" : '') },
          "Role" => lambda {|it| format_user_role_names(it) },
          "Remote" => lambda {|it| display_appliance(@appliance_name, @appliance_url) },
        }, @current_user)
        print cyan

        if options[:include_feature_access]
          if @user_permissions
            print_h2 "Feature Permissions", options
            print cyan
            begin
              rows = []
              if @user_permissions.is_a?(Hash)
                # api used to return map like [code:access]
                rows = @user_permissions.collect do |code, access|
                  {permission: code, access: format_access_string(access) }
                end
              else
                # api now returns an array of objects like [[name:"Foo",code:"foo",access:"full"], ...]
                rows = @user_permissions.collect do |it|
                  {permission: (it['name'] || it['code']), access: format_access_string(it['access']) }
                end
              end
              # api sort sux right now
              rows = rows.sort {|a,b| a[:permission] <=> b[:permission] }
              print as_pretty_table(rows, [:permission, :access], options)
            rescue => ex
              puts_error "Failed to parse feature permissions: #{ex}"
            end
          else
            puts yellow,"No permissions found.",reset
          end
        end

        print reset, "\n"

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

  # Whoami class methods
  class << self
    include Term::ANSIColor

    # @@whoami_cache is for caching the the contents the Whoami api results
    # as YAML files at $home/whoami/$appliance_name/$user_id.json
    @@whoami_cache = nil 

    def whoami_cache
      if @@whoami_cache.nil?
        @@whoami_cache = {}
      end
      return @@whoami_cache
    end

    def clear_whoami_cache(appliance_name, user_id)
      @@whoami_cache ||= {}
      @@whoami_cache[appliance_name.to_s] ||= {}
      @@whoami_cache[appliance_name.to_s][user_id.to_s] = result
    end

    def set_whoami_cache(appliance_name, user_id, result)
      @@whoami_cache ||= {}
      @@whoami_cache[appliance_name.to_s] ||= {}
      @@whoami_cache[appliance_name.to_s][user_id.to_s] = result
    end

    def get_whoami_cache(appliance_name, user_id)
      @@whoami_cache ||= {}
      @@whoami_cache[appliance_name.to_s] ? @@whoami_cache[appliance_name.to_s][user_id.to_s] : nil
    end

    def whoami_file_path
      File.join(Morpheus::Cli.home_directory, "cache", "whoami")
    end

    def save_whoami_file(appliance_name, user_id, json_response)
      fn = File.join(whoami_file_path, appliance_name.to_s, user_id.to_s + ".json")
      if !Dir.exist?(File.dirname(fn))
        FileUtils.mkdir_p(File.dirname(fn))
      end
      Morpheus::Logging::DarkPrinter.puts "writing file #{fn}" if Morpheus::Logging.debug?
      File.open(fn, 'w') {|f| f.write json_response.to_yaml }
      FileUtils.chmod(0600, fn)
      return json_response
    end

    def delete_whoami_file(appliance_name, user_id)
      fn = File.join(whoami_file_path, appliance_name.to_s, user_id.to_s + ".json")
      if File.exist?(fn)
        #Morpheus::Logging::DarkPrinter.puts "deleting file #{fn}" if Morpheus::Logging.debug?
        FileUtils.rm(fn)
      end
      return nil
    end

    def load_whoami_file(appliance_name, user_id)
      raise "appliance_name is required" if appliance_name.to_s.empty?
      raise "user_id is required" if user_id.to_s.empty?
      fn = File.join(whoami_file_path, appliance_name.to_s, user_id.to_s + ".json")
      if File.exist?(fn)
        Morpheus::Logging::DarkPrinter.puts "reading file #{fn}" if Morpheus::Logging.debug?
        return YAML.load_file(fn)
      else
        return nil
      end
    end

    def save_whoami(appliance_name, user_id, result)
      save_whoami_file(appliance_name, user_id, result)
      set_whoami_cache(appliance_name, user_id, result)
    end

    def clear_whoami(appliance_name, user_id)
      delete_whoami_file(appliance_name, user_id)
      set_whoami_cache(appliance_name, user_id, nil)
    end

    def load_whoami(appliance_name, user_id, refresh=false)
      result = nil
      # load from cache (memory) or file or else api
      if refresh == false
        # load from memory
        result = whoami_cache[appliance_name.to_s] ? whoami_cache[appliance_name.to_s][user_id.to_s] : nil
        # load from file
        if result.nil?
          result = load_whoami_file(appliance_name, user_id)
          set_whoami_cache(appliance_name, user_id, result)
        end
      end
      return result
    end

  end

end
