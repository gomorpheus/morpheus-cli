require 'morpheus/api/api_client'
require 'http'
require 'zlib'
require 'forwardable'

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

  # wrapper class for input stream so that HTTP doesn't blow up when using it 
  # ie. calling size() and rewind()
  class BodyIO
    extend Forwardable

    def initialize(io)
      @io = io
    end

    def size
      0
    end

    def rewind
      nil
    end

    def_delegators :@io, :read, :readpartial, :write
    
  end

  # no multipart
  def upload(id, image_file, filename=nil, do_gzip=false)
    filename = filename || File.basename(image_file)
    url = "#{@base_url}/api/virtual-images/#{id}/upload"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:filename] = filename
    payload = image_file
    #execute(method: :post, url: url, headers: headers, payload: payload, timeout: 36000)
    
    # Using http.rb instead of RestClient
    # todo: execute() should support :driver
    
    
    http_opts = {}
    if Morpheus::RestClient.ssl_verification_enabled? == false
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http_opts[:ssl_context] = ctx
      # opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    end
    
    start_time = Time.now
    query_params = headers.delete(:params) || {}
    file_size = image_file.size
    if File.blockdev?(image_file)
      file_size = `blockdev --getsz '#{File.absolute_path(image_file)}'`.strip().to_i
    end
    if do_gzip
      # http = http.use(:auto_deflate)
      headers['Content-Encoding'] = 'gzip'
      headers['Content-Type'] = 'application/gzip'
      headers['Content-Length'] = file_size
      #headers['Transfer-Encoding'] = 'Chunked'
      query_params['extractedContentLength'] = file_size
      if @dry_run
        return {method: :post, url: url, headers: headers, params: query_params, payload: payload}
      end
      http = HTTP.headers(headers)
      http_opts[:params] = query_params
      
      rd, wr = IO.pipe
      Thread.new {
         gz = Zlib::GzipWriter.new(wr)
         File.open(payload) do |fp|
           while chunk = fp.read(10 * 1024 * 1024) do
             gz.write chunk
           end
         end
         gz.close
      }
      http_opts[:body] = BodyIO.new(rd)
      response = http.post(url, http_opts)
    else
      if @dry_run
        return {method: :post, url: url, headers: headers, params: query_params, payload: payload}
      end
      headers['Content-Length'] = file_size
      http = HTTP.headers(headers)
      http_opts[:params] = query_params
      http_opts[:body] = payload
      response = http.post(url, http_opts)
    end
    # puts "Took #{Time.now.to_i - start_time.to_i}"
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
