require 'morpheus/api/api_client'

class Morpheus::PackagesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  # def get(id)
  #   raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
  #   url = "#{@base_url}/api/packages/#{id}"
  #   headers = { params: {}, authorization: "Bearer #{@access_token}" }
  #   opts = {method: :get, url: url, headers: headers}
  #   execute(opts)
  # end

  def list(params={})
    url = "#{@base_url}/api/packages"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(params)
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def search(params={})
    url = "#{@base_url}/api/packages/search"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(params)
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def install(payload)
    url = "#{@base_url}/api/packages/install"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{@base_url}/api/packages/update/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id)
    url = "#{@base_url}/api/packages/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def export(params, outfile)
    url = "#{@base_url}/api/packages/export"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :post, url: url, headers: headers}
    # execute(opts, false)
    if Dir.exists?(outfile)
      raise "outfile is invalid. It is the name of an existing directory: #{outfile}"
    end
    # if @verify_ssl == false
    #   opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    # end
    if @dry_run
      return opts
    end
    http_response = nil
    bad_body = nil
    File.open(outfile, 'w') {|f|
      block = proc { |response|
        if response.code.to_i == 200
          response.read_body do |chunk|
              #puts "writing to #{outfile} ..."
              f.write chunk
          end
        else
          # puts_error (#{response.inspect}) #{chunk} ..."
          bad_body = response.body.to_s
        end
      }
      opts[:block_response] = block
      http_response = RestClient::Request.new(opts).execute
      # RestClient::Request.execute(opts)
    }
    return http_response, bad_body
  end


end
