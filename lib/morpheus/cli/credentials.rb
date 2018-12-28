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
      
      def request_credentials(opts = {})
        #puts "request_credentials(#{opts})"
        username = nil
        password = nil
        access_token = nil
        skip_save = false
        
        if opts[:remote_token]
          begin
            whoami_interface = Morpheus::WhoamiInterface.new(opts[:remote_token], nil, nil, @appliance_url)
            whoami_response = whoami_interface.get()
            if opts[:json]
              print JSON.pretty_generate(whoami_response)
              print reset, "\n"
            end
            access_token = opts[:remote_token]
            username = whoami_response['user']['username']
            unless skip_save
              save_credentials(@appliance_name, access_token)
            end
          rescue ::RestClient::Exception => e
            #raise e
            print_red_alert "Token not valid."
            if opts[:debug] || opts[:debug]
              print_rest_exception(e, opts)
            end
            access_token = nil
          end
        else
        
          if !opts[:remote_username].nil?
            username = opts[:remote_username]
            password = opts[:remote_password]
            skip_save = opts[:remote_url] ? true : false
          else
            access_token = load_saved_credentials
          end
          if access_token
            return access_token
          end
          unless opts[:quiet] || opts[:no_prompt]
            # if username.empty? || password.empty?
              print "Enter Morpheus Credentials for #{display_appliance(@appliance_name, @appliance_url)}\n",reset
            # end
            if username.empty?
              print "Username: #{required_blue_prompt} "
              username = $stdin.gets.chomp!
            else
              print "Username: #{required_blue_prompt} #{username}\n"
            end
            if password.empty?
              print "Password: #{required_blue_prompt} "
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
            json_response = auth_interface.login(username, password)
            if opts[:json]
              print JSON.pretty_generate(json_response)
              print reset, "\n"
            end
            access_token = json_response['access_token']
            if access_token && access_token != ""
              unless skip_save
                save_credentials(@appliance_name, access_token)
              end
              # return access_token
            else
              print_red_alert "Credentials not verified."
              # return nil
            end
          rescue ::RestClient::Exception => e
            #raise e
            if (e.response && e.response.code == 400)
              json_response = JSON.parse(e.response.to_s)
              error_msg = json_response['error_description'] || "Credentials not verified."
              print_red_alert error_msg
              if opts[:json]
                json_response = JSON.parse(e.response.to_s)
                print JSON.pretty_generate(json_response)
                print reset, "\n"
              end
            else
              print_rest_exception(e, opts)
            end
            access_token = nil
          end

        end


        unless skip_save
          begin
          # save pertinent session info to the appliance
            now = Time.now.to_i
            appliance = ::Morpheus::Cli::Remote.load_remote(@appliance_name)
            if appliance
              if access_token
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
            #puts "failed to update remote appliance config: (#{e.class}) #{e.message}"
          end
        end

        return access_token
      end

      def login(opts = {})
        clear_saved_credentials(@appliance_name)
        request_credentials(opts)
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
        true
      end

      def clear_saved_credentials(appliance_name)
        @@appliance_credentials_map = load_credentials_file || {}
        @@appliance_credentials_map.delete(appliance_name)
        Morpheus::Logging::DarkPrinter.puts "clearing credentials for #{appliance_name} from file #{credentials_file_path}" if Morpheus::Logging.debug?
        File.open(credentials_file_path, 'w') {|f| f.write @@appliance_credentials_map.to_yaml } #Store
      end

      def load_saved_credentials(reload=false)
        if reload || !defined?(@@appliance_credentials_map) || @@appliance_credentials_map.nil?
          @@appliance_credentials_map = load_credentials_file || {}
        end
        return @@appliance_credentials_map[@appliance_name]
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

      def save_credentials(appliance_name, token)
        # credential_map = appliance_credentials_map
        # reloading file is better for now, otherwise you can lose credentials with multiple shells.
        credential_map = load_credentials_file || {}
        if credential_map.nil?
          credential_map = {}
        end
        credential_map[appliance_name] = token
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
        end
      end
    end
  end
end
