require 'yaml'
require 'io/console'
require 'optparse'

module Morpheus
	module Cli
		class Credentials
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
					if username.nil? || username.empty?
						puts "Enter Username: "
						username = $stdin.gets.chomp!
					end
					if password.nil? || password.empty?
						puts "Enter Password: "
						password = STDIN.noecho(&:gets).chomp!
					end
					oauth_url = File.join(@appliance_url, "/oauth/token")
					begin
						authorize_response = Morpheus::RestClient.execute(method: :post, url: oauth_url, headers:{ params: {grant_type: 'password', scope:'write', client_id: 'morph-cli', username: username}}, payload: {password: password},verify_ssl: false)
						json_response = JSON.parse(authorize_response.to_s)
						access_token = json_response['access_token']
						if access_token

							save_credentials(access_token) unless skip_save
							return access_token
						else
							puts "Credentials not verified."
							return nil
						end
					rescue => e
						puts "Error Communicating with the Appliance. Please try again later. #{e}"
						return nil
					end
				else
					return creds
				end
			end

			def login()
				clear_saved_credentials
				request_credentials
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
