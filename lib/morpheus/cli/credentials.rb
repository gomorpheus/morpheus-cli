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

      @@saved_credentials_map = nil

      def initialize(appliance_name, appliance_url)
        @appliance_url = appliance_url
        @appliance_name = appliance_name
      end
      
      def request_credentials(opts = {})
        #puts "request_credentials(#{opts})"
        username = nil
        password = nil
        creds = nil
        skip_save = false
        # We should return an access Key for Morpheus CLI Here
        if !opts[:remote_username].nil?
          username = opts[:remote_username]
          password = opts[:remote_password]
          skip_save = opts[:remote_url] ? true : false
        else
          creds = load_saved_credentials
        end
        if creds
          return creds
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
          if !access_token.empty?
            unless skip_save
              save_credentials(@appliance_name, access_token)
            end
            return access_token
          else
            print_red_alert "Credentials not verified."
            return nil
          end
        rescue ::RestClient::Exception => e
          #raise e
          if (e.response && e.response.code == 400)
            print_red_alert "Credentials not verified."
            if opts[:json]
              json_response = JSON.parse(e.response.to_s)
              print JSON.pretty_generate(json_response)
              print reset, "\n"
            end
          else
            print_rest_exception(e, opts)
          end
        end

      end

      def login(opts = {})
        clear_saved_credentials(@appliance_name)
        request_credentials(opts)
      end

      def logout()
        clear_saved_credentials(@appliance_name)
      end

      def clear_saved_credentials(appliance_name)
        @@saved_credentials_map = load_credentials_file || {}
        @@saved_credentials_map.delete(appliance_name)
        Morpheus::Logging::DarkPrinter.puts "updating credentials file #{credentials_file_path}" if Morpheus::Logging.debug?
        File.open(credentials_file_path, 'w') {|f| f.write @@saved_credentials_map.to_yaml } #Store
      end

      def load_saved_credentials(reload=false)
        if saved_credentials_map && !reload
          return saved_credentials_map
        end
        @@saved_credentials_map = load_credentials_file || {}
        return @@saved_credentials_map[@appliance_name]
      end

      # Provides the current credential information, simply :appliance_name => "access_token"
      def saved_credentials_map
        if !defined?(@@saved_credentials_map)
          @@saved_credentials_map = load_credentials_file
        end
        return @@saved_credentials_map ? @@saved_credentials_map[@appliance_name.to_sym] : nil
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

      def save_credentials(app_name, token)
        # credential_map = saved_credentials_map
        # reloading file is better for now, otherwise you can lose credentials with multiple shells.
        credential_map = load_credentials_file || {}
        if credential_map.nil?
          credential_map = {}
        end
        credential_map[app_name] = token
        begin
          fn = credentials_file_path
          if !Dir.exists?(File.dirname(fn))
            FileUtils.mkdir_p(File.dirname(fn))
          end
          Morpheus::Logging::DarkPrinter.puts "adding credentials for #{app_name} to #{fn}" if Morpheus::Logging.debug?
          File.open(fn, 'w') {|f| f.write credential_map.to_yaml } #Store
          FileUtils.chmod(0600, fn)
        rescue => e
          puts "failed to save #{fn}. #{e}"  if Morpheus::Logging.debug?
        end
      end
    end
  end
end
