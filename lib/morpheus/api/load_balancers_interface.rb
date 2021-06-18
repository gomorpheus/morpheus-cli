require 'morpheus/api/api_client'

class Morpheus::LoadBalancersInterface < Morpheus::APIClient

  def load_balancer_types(options={})
    url = "#{@base_url}/api/load-balancer-types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/load-balancer-types/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    execute(method: :get, url: url, headers: headers)
  end

  def list(params={})
    url = "#{@base_url}/api/load-balancers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end
  
  def get(options=nil)
    url = "#{@base_url}/api/load-balancers"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/load-balancers/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    execute(method: :get, url: url, headers: headers)
  end

  def update(id, options)
    url = "#{@base_url}/api/load-balancers/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end


  def create(options)
    url = "#{@base_url}/api/load-balancers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id)
    url = "#{@base_url}/api/load-balancers/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
end
