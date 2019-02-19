require 'morpheus/api/api_client'
require 'uri'

class Morpheus::CypherVaultInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(item_key, params={}, options={})
    raise "#{self.class}.get() passed a blank item_key!" if item_key.to_s == ''
    url = "#{@base_url}/api/cypher/v1/#{item_key}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers}, options)
  end

  # list url is the same as get but uses $itemKey/?list=true
  # method: 'LIST' would be neat though
  def list(item_key=nil, params={}, options={})
    url = item_key ? "#{@base_url}/api/cypher/v1/#{item_key}" : "#{@base_url}/api/cypher/v1"
    params.merge!({list:'true'})
    headers = { params: params, authorization: "Bearer #{@access_token}" }.merge(options[:headers] || {})
    execute({method: :get, url: url, headers: headers}, options)
  end

  def create(item_key, payload, options={})
    url = "#{@base_url}/api/cypher/v1/#{item_key}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute({method: :post, url: url, headers: headers, payload: payload.to_json}, options)
  end

  def update(item_key, payload, options={})
    url = "#{@base_url}/api/cypher/v1/#{item_key}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute({method: :put, url: url, headers: headers, payload: payload.to_json}, options)
  end

  def destroy(item_key, params={}, options={})
    url = "#{@base_url}/api/cypher/v1/#{item_key}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute({method: :delete, url: url, headers: headers}, options)
  end

end
