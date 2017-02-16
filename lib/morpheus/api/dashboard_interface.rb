require 'json'
require 'rest-client'

class Morpheus::DashboardInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

  def get(options={})
    dashboard(options)
  end

  def dashboard(options={})
    url = "#{@base_url}/api/dashboard"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers)
    JSON.parse(response.to_s)
  end

	def recent_activity(account_id=nil, options={})
    url = "#{@base_url}/api/dashboard/recentActivity"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    headers[:params]['accountId'] = account_id if account_id
    response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
    JSON.parse(response.to_s)
  end

	

end
