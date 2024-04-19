require 'morpheus/api/api_client'

class Morpheus::EmailTemplatesInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/email-templates"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  # def get(options=nil)
  #   url = "#{@base_url}/api/tasks"
  #   headers = { params: {}, authorization: "Bearer #{@access_token}" }

  #   if options.is_a?(Hash)
  #     headers[:params].merge!(options)
  #   elsif options.is_a?(Numeric)
  #     url = "#{@base_url}/api/tasks/#{options}"
  #   elsif options.is_a?(String)
  #     headers[:params]['name'] = options
  #   end
  #   execute(method: :get, url: url, headers: headers)
  # end

  # def update(id, options)
  #   url = "#{@base_url}/api/tasks/#{id}"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   payload = options
  #   execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  # end


  # def create(options)
  #   url = "#{@base_url}/api/tasks"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   payload = options
  #   execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  # end

  # def destroy(id, params={})
  #   url = "#{@base_url}/api/tasks/#{id}"
  #   headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   execute(method: :delete, url: url, headers: headers)
  # end

  # def run(id, options)
  #   url = "#{@base_url}/api/tasks/#{id}/execute"
  #   headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  #   payload = options
  #   execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  # end

  # def list_types(params={})
  #   url = "#{@base_url}/api/task-types"
  #   headers = { params: params, authorization: "Bearer #{@access_token}" }
  #   execute(method: :get, url: url, headers: headers)
  # end

  # def get_type(id, params={})
  #   url = "#{@base_url}/api/task-types/#{id}"
  #   headers = { params: params, authorization: "Bearer #{@access_token}" }
  #   execute(method: :get, url: url, headers: headers)
  # end

end