require 'morpheus/api/api_client'

class Morpheus::TaskSetsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(options=nil)
    url = "#{@base_url}/api/task-sets"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/task-sets/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    execute(method: :get, url: url, headers: headers)
  end


  def create(options)
    url = "#{@base_url}/api/task-sets"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, options)
    url = "#{@base_url}/api/task-sets/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id)
    url = "#{@base_url}/api/task-sets/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
end
