require 'morpheus/api/api_client'

class Morpheus::ReportsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/reports/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list(params={})
    url = "#{@base_url}/api/reports"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = "#{@base_url}/api/reports"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  # def update(id, payload)
  #   url = "#{@base_url}/api/reports/#{id}"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  # end

  def destroy(id, params={})
    url = "#{@base_url}/api/reports/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    execute(method: :delete, url: url, headers: headers)
  end

  def types(params={})
    url = "#{@base_url}/api/report-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def export(id, outfile, params={}, report_format='json')
    url = "#{@base_url}/api/reports/export/#{id}.#{report_format}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers, timeout: 172800}
    # execute(opts, {parse_json: false})
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
    File.open(outfile, 'w') {|f|
      block = proc { |response|
        response.read_body do |chunk|
          # writing to #{outfile} ..."
          f.write chunk
        end
      }
      opts[:block_response] = block
      http_response = Morpheus::RestClient.execute(opts)
    }
    return http_response
  end

end
