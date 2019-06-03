require 'morpheus/api/api_client'

class Morpheus::SecurityGroupRulesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end


  def get(security_group_id, options=nil)
    url = "#{@base_url}/api/security-groups/#{security_group_id}/rules"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/security-groups/#{security_group_id}/rules/#{options}"
    end
    execute(method: :get, url: url, headers: headers)
  end

  def create(security_group_id, options)
    url = "#{@base_url}/api/security-groups/#{security_group_id}/rules"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(security_group_id, id, payload)
    url = "#{@base_url}/api/security-groups/#{security_group_id}/rules/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def delete(security_group_id, id)
    url = "#{@base_url}/api/security-groups/#{security_group_id}/rules/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
end
