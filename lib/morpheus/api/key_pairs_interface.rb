require 'json'
require 'rest-client'

class Morpheus::KeyPairsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(account_id, id)
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/key-pairs/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params]['accountId'] = account_id if account_id
    response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
    JSON.parse(response.to_s)
  end

  def list(account_id, options={})
    url = "#{@base_url}/api/key-pairs"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    headers[:params]['accountId'] = account_id if account_id
    response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
    JSON.parse(response.to_s)
  end

  def create(account_id, options)
    url = "#{@base_url}/api/key-pairs"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers[:params]['accountId'] = account_id if account_id
    payload = options
    response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
    JSON.parse(response.to_s)
  end

  def update(account_id, id, options)
    url = "#{@base_url}/api/key-pairs/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers[:params]['accountId'] = account_id if account_id
    payload = options
    response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
    JSON.parse(response.to_s)
  end

  def destroy(account_id, id)
    url = "#{@base_url}/api/key-pairs/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers[:params]['accountId'] = account_id if account_id
    response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 10, headers: headers)
    JSON.parse(response.to_s)
  end
end
