require 'fileutils'
require 'yaml'
require 'json'
require 'io/console'
require 'rest_client'
require 'morpheus/logging'
require 'morpheus/cli/mixins/print_helper'

module Morpheus
  module Cli
    class Credentials
      include Morpheus::Cli::PrintHelper

      @@appliance_credentials_map = nil

      def initialize(appliance_name, appliance_url)
        @appliance_name = appliance_name ? appliance_name.to_sym : nil
        @appliance_url = appliance_url
      end
      
      # request_credentials will fetch a credentials wallet (access_token, refresh_token, etc)
      # By default this uses the saved credentials for the current appliance.
      # If not logged in, it will prompt for username and password to
      # authenticate with the /oauth/token API to receive an access_token.
      # If :username and :password are passed, then
      # Pass :remote_token to skip prompting and the auth api request.
      # @param options - Hash of optional settings.
      #   :username - Username to use, skips saved lookup and prompting.
      #   :password - Password to use, skips saved lookup and prompting.
      #   :remote_url - Use this url instead of the one from the current appliance. Credentials will not be saved.
      #   :remote_token - Use this access_token, skip prompting and API request.
      #   :test_only - Test only. Saved credentials will not be updated.
      # @return Hash wallet like {"access_token":"ec68be138765...", "refresh_token":"ec68be138765..."} 
      # or nil if unable to find credentials.
      def request_credentials(options = {})
        #puts "request_credentials(#{options})"
        username = nil
        password = nil
        wallet = nil
        skip_save = false
        if options[:skip_save] == true || options[:test_only] == true || options[:remote_url] == true || options[:dry_run] == true
          skip_save = true
        end

        # logout/ clear credentials
        unless skip_save
          clear_saved_credentials(@appliance_name)
          appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
          if appliance
            appliance.delete(:username)
            appliance[:authenticated] = false
            appliance[:last_logout_at] = Time.now.to_i
            ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
            ::Morpheus::Cli::Remote.recalculate_variable_map()
          end
        end

        if options[:remote_token]
          # user passed in a token to login with.
          # this should get token info from /oauth/token
          # OR whoami should return other wallet info like access token or maybe just the expiration date
          # for now, it just stores the access token without other wallet info
          begin
            whoami_interface = Morpheus::WhoamiInterface.new(options[:remote_token], nil, nil, @appliance_url)
            if options[:dry_run]
              print_dry_run whoami_interface.dry.get()
              return nil
            end
            whoami_response = whoami_interface.get()
            if options[:json]
              print JSON.pretty_generate(whoami_response)
              print reset, "\n"
            end
            # store mock /oauth/token  auth_interface.login() result
            json_response = {'access_token' => options[:remote_token], 'token_type' => 'bearer'}
            username = whoami_response['user']['username']
            login_date = Time.now
            expire_date = nil
            if json_response['expires_in']
              expire_date = login_date.to_i + json_response['expires_in'].to_i
            end
            wallet = {
              'username' => username, 
              'login_date' => login_date.to_i,
              'expire_date' => expire_date ? expire_date.to_i : nil,
              'access_token' => json_response['access_token'], 
              'refresh_token' => json_response['refresh_token'], 
              'token_type' => json_response['token_type']
            }
            unless skip_save
              save_credentials(@appliance_name, wallet)
            end
          rescue ::RestClient::Exception => e
            #raise e
            print_red_alert "Token not valid."
            if options[:debug] || options[:debug]
              print_rest_exception(e, options)
            end
            wallet = nil
          end
        else
        
          # JD: I think this might be wonky, :username global option is overlapping with the one from login, fix it
          # if passing a username on the fly (skip_save)
          # that's assumed to be a transient command, not one to log yo in (update your session)
          # that should be done outside of this method you see...
          if options[:username]
            username = options[:username]
            password = options[:password]
            if skip_save == false
              #skip_save = (options[:remote_url] ? true : false)
            end
          else
            # maybe just if check if options[:test_only] != true
            if skip_save == false
              wallet = load_saved_credentials
            end  
          end

          if wallet.nil?
            unless options[:quiet] || options[:no_prompt]
              # if username.empty? || password.empty?
                if options[:test_only]
                  print "Test Morpheus Credentials @ #{display_appliance(@appliance_name, @appliance_url)}\n",reset
                else
                  print "Enter Morpheus Credentials @ #{display_appliance(@appliance_name, @appliance_url)}\n",reset
                end
              # end
              if username.empty?
                print "Username: #{required_blue_prompt} "
                username = $stdin.gets.chomp!
              else
                print "Username: #{required_blue_prompt} #{username}\n"
              end
              if password.empty?
                print "Password: #{required_blue_prompt} "
                # wtf is this STDIN and $stdin and not my_terminal.stdin ?
                password = STDIN.noecho(&:gets).chomp!
                print "\n"
              else
                print "Password: #{required_blue_prompt} \n"
              end
            end
            if username.empty? || password.empty?
              print_red_alert "Username and password are required to login."
              return nil
            end
            begin
              auth_interface = Morpheus::AuthInterface.new(@appliance_url)
              auth_interface.setopts(options)
              if options[:dry_run]
                print_dry_run auth_interface.dry.login(username, password)
                return nil
              end
              json_response = auth_interface.login(username, password)
              if options[:json]
                print JSON.pretty_generate(json_response)
                print reset, "\n"
              end
              #wallet = json_response
              login_date = Time.now
              expire_date = nil
              if json_response['expires_in']
                expire_date = login_date.to_i + json_response['expires_in'].to_i
              end
              wallet = {
                'username' => username, 
                'login_date' => login_date.to_i,
                'expire_date' => expire_date ? expire_date.to_i : nil,
                'access_token' => json_response['access_token'], 
                'refresh_token' => json_response['refresh_token'], 
                'token_type' => json_response['token_type']
              }

            rescue ::RestClient::Exception => e
              #raise e
              if (e.response && e.response.code == 400)
                json_response = JSON.parse(e.response.to_s)
                error_msg = json_response['error_description'] || "Credentials not verified."
                print_red_alert error_msg
                if options[:json]
                  json_response = JSON.parse(e.response.to_s)
                  print JSON.pretty_generate(json_response)
                  print reset, "\n"
                end
              else
                print_rest_exception(e, options)
              end
              wallet = nil
            end

          end
        end


        unless skip_save

          # save wallet to credentials file
          save_credentials(@appliance_name, wallet)

          begin
          # save pertinent session info to the appliance
            now = Time.now.to_i
            appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
            if appliance
              if wallet && wallet['access_token']
                appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
                appliance[:authenticated] = true
                appliance[:username] = username
                appliance[:status] = "ready"
                appliance[:last_login_at] = now
                appliance[:last_success_at] = now
                ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
              else
                now = Time.now.to_i
                appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
                appliance[:authenticated] = false
                #appliance[:username] = username
                #appliance[:last_login_at] = now
                #appliance[:error] = "Credentials not verified"
                ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
              end
            end
          rescue => e
            Morpheus::Logging::DarkPrinter.puts "failed to update remote appliance config: (#{e.class}) #{e.message}"
          end
        end
        
        return wallet
      end

      def login(options = {})
        request_credentials(options)
      end

      def logout()
        clear_saved_credentials(@appliance_name)
        # save pertinent session info to the appliance
        appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
        if appliance
          appliance.delete(:username) # could leave this...
          appliance[:authenticated] = false
          appliance[:last_logout_at] = Time.now.to_i
          ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
        end
        ::Morpheus::Cli::Remote.recalculate_variable_map()
        true
      end

      def use_refresh_token(options = {})
        #puts "use_refresh_token(#{options})"
        
        wallet = load_saved_credentials

        if wallet.nil?
          print_red_alert yellow,"You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
          return nil
        end

        if wallet['refresh_token'].nil?
          print_red_alert yellow,"No refresh token found for #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
          return nil
        end


        username = wallet['username']

        begin
          auth_interface.setopts(options)
          auth_interface = Morpheus::AuthInterface.new(@appliance_url)
          if options[:dry_run]
            print_dry_run auth_interface.dry.use_refresh_token(wallet['refresh_token'])
            return nil
          end
          json_response = auth_interface.use_refresh_token(wallet['refresh_token'])
          #wallet = json_response
          login_date = Time.now
          expire_date = nil
          if json_response['expires_in']
            expire_date = login_date.to_i + json_response['expires_in'].to_i
          end
          wallet = {
            'username' => username, 
            'login_date' => login_date.to_i,
            'expire_date' => expire_date ? expire_date.to_i : nil,
            'access_token' => json_response['access_token'], 
            'refresh_token' => json_response['refresh_token'], 
            'token_type' => json_response['token_type']
          }
          
        rescue ::RestClient::Exception => e
          #raise e
          if (e.response && e.response.code == 400)
            json_response = JSON.parse(e.response.to_s)
            error_msg = json_response['error_description'] || "Refresh token not valid."
            print_red_alert error_msg
            if options[:json]
              json_response = JSON.parse(e.response.to_s)
              print JSON.pretty_generate(json_response)
              print reset, "\n"
            end
          else
            print_rest_exception(e, options)
          end
          wallet = nil
        end

        # save wallet to credentials file
        save_credentials(@appliance_name, wallet)

        begin
        # save pertinent session info to the appliance
          now = Time.now.to_i
          appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
          if appliance
            if wallet && wallet['access_token']
              appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
              appliance[:authenticated] = true
              appliance[:username] = username
              appliance[:status] = "ready"
              appliance[:last_login_at] = now
              appliance[:last_success_at] = now
              ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
            else
              now = Time.now.to_i
              appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
              appliance[:authenticated] = false
              #appliance[:username] = username
              #appliance[:last_login_at] = now
              #appliance[:error] = "Credentials not verified"
              ::Morpheus::Cli::Remote.save_remote(@appliance_name, appliance)
            end
          end
        rescue => e
          Morpheus::Logging::DarkPrinter.puts "failed to update remote appliance config: (#{e.class}) #{e.message}"
        end
        
        
        return wallet
      end

      def clear_saved_credentials(appliance_name)
        @@appliance_credentials_map = load_credentials_file || {}
        @@appliance_credentials_map.delete(appliance_name.to_s)
        @@appliance_credentials_map.delete(appliance_name.to_sym)
        Morpheus::Logging::DarkPrinter.puts "clearing credentials for #{appliance_name} from file #{credentials_file_path}" if Morpheus::Logging.debug?
        File.open(credentials_file_path, 'w') {|f| f.write @@appliance_credentials_map.to_yaml } #Store
        ::Morpheus::Cli::Remote.recalculate_variable_map()
        true
      end

      def load_saved_credentials(reload=false)
        if reload || !defined?(@@appliance_credentials_map) || @@appliance_credentials_map.nil?
          @@appliance_credentials_map = load_credentials_file || {}
        end
        # ok, we switched  symbols to strings, because symbols suck in yaml! need to support both
        # also we switched from just a token (symbol) to a whole object of strings
        wallet = @@appliance_credentials_map[@appliance_name.to_s] || @@appliance_credentials_map[@appliance_name.to_sym]
        if wallet.is_a?(String)
          wallet = {'access_token' => wallet}
        end
        return wallet
      end

      def load_credentials_file
        fn = credentials_file_path
        if File.exist? fn
          Morpheus::Logging::DarkPrinter.puts "loading credentials file #{fn}" if Morpheus::Logging.debug?
          return YAML.load_file(fn)
        else
          return nil
        end
      end

      def credentials_file_path
        File.join(Morpheus::Cli.home_directory, "credentials")
      end

      # credentials wallet is {'access_token': '...', 'refresh_token': '...' 'expiration': '2019-01-01...'}
      def save_credentials(appliance_name, wallet)
        # reloading file is better for now, otherwise you can lose credentials with multiple shells.
        credential_map = load_credentials_file || {}
        
        if wallet
          credential_map[appliance_name.to_s] = wallet
        else
          # nil mean remove the damn thing
          credential_map.delete(appliance_name.to_s)
        end
        # always remove symbol, which was used pre 3.6.9
        credential_map.delete(appliance_name.to_sym)
        begin
          fn = credentials_file_path
          if !Dir.exists?(File.dirname(fn))
            FileUtils.mkdir_p(File.dirname(fn))
          end
          Morpheus::Logging::DarkPrinter.puts "adding credentials for #{appliance_name} to #{fn}" if Morpheus::Logging.debug?
          File.open(fn, 'w') {|f| f.write credential_map.to_yaml } #Store
          FileUtils.chmod(0600, fn)
          @@appliance_credentials_map = credential_map
        rescue => e
          puts "failed to save #{fn}. #{e}"  if Morpheus::Logging.debug?
        ensure
          # recalcuate echo vars
          #puts "Recalculating variable maps for username change"
          Morpheus::Cli::Echo.recalculate_variable_map()
          # recalculate shell prompt after this change
          if Morpheus::Cli::Shell.has_instance?
            Morpheus::Cli::Shell.instance.reinitialize()
          end
        end
      end
    end
  end
end
