require 'morpheus/api/api_client'
require 'http'

class Morpheus::VirtualImagesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def virtual_image_types(options={})
    url = "#{@base_url}/api/virtual-image-types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    end
    execute(method: :get, url: url, headers: headers)
  end

  def get(options=nil)
    url = "#{@base_url}/api/virtual-images"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/virtual-images/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    execute(method: :get, url: url, headers: headers)
  end

  def list(options=nil)
    url = "#{@base_url}/api/virtual-images"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = "#{@base_url}/api/virtual-images"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{@base_url}/api/virtual-images/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id)
    url = "#{@base_url}/api/virtual-images/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  # multipart file upload
  # def upload(id, image_file)
  #   url = "#{@base_url}/api/virtual-images/#{id}/upload"
  #   headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
  #   payload = {}
  #   payload[:file] = image_file
  #   payload[:multipart] = true
  #   execute(method: :post, url: url, headers: headers, payload: payload)
  # end

  # no multipart
  def upload(id, image_file, filename=nil)
    filename = filename || File.basename(image_file)
    url = "#{@base_url}/api/virtual-images/#{id}/upload"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:filename] = filename
    payload = image_file
    #execute(method: :post, url: url, headers: headers, payload: payload, timeout: 36000)

    # todo: execute() should support different :driver values
    # this is the http.rb way, for streaming IO anyhow..
    if @dry_run
      return {method: :post, url: url, headers: headers, payload: payload, timeout: 36000}
    end
    
    http_opts = {}
    if @verify_ssl == false
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http_opts[:ssl_context] = ctx
      # opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    end
    if @dry_run
      # JD: could return a Request object instead...
      return opts
    end
    http_opts[:body] = payload
    query_params = headers.delete(:params)
    if query_params
      http_opts[:params] = query_params
    end
    http = HTTP.headers(headers)
    response = http.post(url, http_opts)
    # return response
    return JSON.parse(response.body.to_s)
  end

  def upload_by_url(id, file_url, filename=nil)
    url = "#{@base_url}/api/virtual-images/#{id}/upload"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:url] = file_url
    headers[:params][:filename] = filename if filename
    execute(method: :post, url: url, headers: headers, timeout: 36000)
  end

  def destroy_file(id, filename)
    url = "#{@base_url}/api/virtual-images/#{id}/files"
    #url = "#{@base_url}/api/virtual-images/#{id}/files/#{filename}"
    headers = { params: {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers[:params][:filename] = filename
    execute(method: :delete, url: url, headers: headers)
  end

end
