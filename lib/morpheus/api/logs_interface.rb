require 'json'
require 'rest-client'

class Morpheus::LogsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def container_logs(containers=[], options={})
		url = "#{@base_url}/api/logs"
		headers = { params: {'containers' => containers}.merge(options), authorization: "Bearer #{@access_token}" }
		opts = {method: :get, url: url, headers: headers}
		execute(opts)
	end

	def server_logs(servers=[], options={})
		url = "#{@base_url}/api/logs"
		headers = { params: {'servers' => servers}.merge(options), authorization: "Bearer #{@access_token}" }
		opts = {method: :get, url: url, headers: headers}
		execute(opts)
	end

	def stats()
		url = "#{@base_url}/api/logs/log-stats"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		opts = {method: :get, url: url, headers: headers}
		execute(opts)
	end


end
