require 'morpheus/api/api_client'
require 'uri'

class Morpheus::CypherInterface < Morpheus::APIClient

  def base_path
    "/api/cypher"
  end

  def get(item_key, params={})
    raise "#{self.class}.get() passed a blank item_key!" if item_key.to_s == ''
    url = "#{@base_url}#{base_path}/#{item_key}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end

  # list url is the same as get but uses $itemKey/?list=true
  # method: 'LIST' would be neat though
  def list(item_key=nil, params={})
    url = item_key ? "#{@base_url}#{base_path}/#{item_key}" : "#{@base_url}#{base_path}"
    params.merge!({list:'true'}) # ditch this probably
    headers = { :params => params, :authorization => "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end

  def create(item_key, params={}, payload={})
    url = "#{@base_url}#{base_path}/#{item_key}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute({method: :post, url: url, headers: headers, payload: payload.to_json})
  end

  # update is not even needed I don't think, same as POST
  def update(item_key, params={}, payload={})
    url = "#{@base_url}#{base_path}/#{item_key}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute({method: :put, url: url, headers: headers, payload: payload.to_json})
  end

  def destroy(item_key, params={})
    url = "#{@base_url}#{base_path}/#{item_key}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute({method: :delete, url: url, headers: headers})
  end

end
