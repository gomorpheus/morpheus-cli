require 'yaml'
require 'io/console'
require 'rest_client'
#require 'optparse'
require 'morpheus/logging'
require 'morpheus/cli/mixins/print_helper'
require 'json'

module Morpheus
	module Cli
		class Credentials
			include Morpheus::Cli::PrintHelper

			def initialize(appliance_name, appliance_url)
				@appliance_url = appliance_url
				@appliance_name = appliance_name
			end
			
			def request_credentials(opts = {})
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
				if !creds
					print "\nEnter Morpheus Credentials for #{@appliance_name} - #{@appliance_url}\n\n",reset
					if username.nil? || username.empty?
						# print "Username: "
						print "Username: #{required_blue_prompt} "
						username = $stdin.gets.chomp!
					end
					if password.nil? || password.empty?
						# print "Password: "
						print "Password: #{required_blue_prompt} "
						password = STDIN.noecho(&:gets).chomp!
						print "\n"
					end

					oauth_url = File.join(@appliance_url, "/oauth/token")
					begin
						authorize_response = Morpheus::RestClient.execute(method: :post, url: oauth_url, headers:{ params: {grant_type: 'password', scope:'write', client_id: 'morph-cli', username: username}}, payload: {password: password},verify_ssl: false, timeout: 10)

						json_response = JSON.parse(authorize_response.to_s)
						access_token = json_response['access_token']
						if !access_token.empty?
							save_credentials(access_token) unless skip_save
							return access_token
						else
							print_red_alert "Credentials not verified."
							return nil
						end
					rescue ::RestClient::Exception => e
						if (e.response && e.response.code == 400)
							print_red_alert "Credentials not verified."
							if opts[:json]
								json_response = JSON.parse(e.response.to_s)
								print JSON.pretty_generate(json_response)
          			print reset, "\n\n"
							end
						else
							print_rest_exception(e, opts)
						end
						exit 1
					rescue => e
						print_red_alert "Error Communicating with the Appliance. #{e}"
						exit 1
					end
				else
					return creds
				end
			end

			def login(opts = {})
				clear_saved_credentials
				request_credentials(opts)
			end

			def logout()
				clear_saved_credentials
			end

			def clear_saved_credentials()
				credential_map = load_credential_file
				if credential_map.nil?
					credential_map = {}
				end
				credential_map.delete(@appliance_name)
				File.open(credentials_file_path, 'w') {|f| f.write credential_map.to_yaml } #Store
			end

			def load_saved_credentials()
				credential_map = load_credential_file
				if credential_map.nil?
					return nil
				else
					return credential_map[@appliance_name]
				end
			end

			def load_credential_file
				creds_file = credentials_file_path
				if File.exist? creds_file
					return YAML.load_file(creds_file)
				else
					return nil
				end
			end

			def credentials_file_path
				home_dir = Dir.home
				morpheus_dir = File.join(home_dir,".morpheus")
				if !Dir.exist?(morpheus_dir)
					Dir.mkdir(morpheus_dir)
				end
				return File.join(morpheus_dir,"credentials")
			end

			def save_credentials(token)
				credential_map = load_credential_file
				if credential_map.nil?
					credential_map = {}
				end
				credential_map[@appliance_name] = token
				File.open(credentials_file_path, 'w') {|f| f.write credential_map.to_yaml } #Store
			end
		end
	end
end
