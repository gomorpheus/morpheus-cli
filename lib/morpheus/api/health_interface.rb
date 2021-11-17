require 'morpheus/api/api_client'

class Morpheus::HealthInterface < Morpheus::APIClient

  def get(params={})
    url = "#{@base_url}/api/health"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def live(params={})
    url = "#{@base_url}/api/health/live"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def alarms(params={})
    list_alarms(params)
  end

  def list_alarms(params={})
    url = "#{@base_url}/api/health/alarms"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get_alarm(id, params={})
    raise "#{self.class}.get() passed a blank name!" if id.to_s == ''
    url = "#{@base_url}/api/health/alarms/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def acknowledge_alarm(id, params={}, payload={})
    url = "#{@base_url}/api/health/alarms/#{id}/acknowledge"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def acknowledge_alarms(params, payload={})
    url = "#{@base_url}/api/health/alarms/acknowledge"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def notifications(params={})
    url = "#{@base_url}/api/health/notifications"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def logs(params={})
    url = "#{@base_url}/api/health/logs"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def export_logs(outfile, params={})
    url = "#{@base_url}/api/health/logs/export"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
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
      http_response = Morpheus::RestClient.execute(opts)
    }
    return http_response, bad_body
  end

end
