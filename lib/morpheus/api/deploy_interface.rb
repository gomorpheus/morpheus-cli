require 'morpheus/api/api_client'
require 'net/http/post/multipart'
require 'mime/types'

class Morpheus::DeployInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end


  def get(instanceId, options=nil)
    url = "#{@base_url}/api/instances/#{instanceId}/deploy"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    execute(method: :get, url: url, headers: headers)
  end


  def create(instanceId, options=nil)
    url = "#{@base_url}/api/instances/#{instanceId}/deploy"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options || {}
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def list_files(id)
    url = "#{@base_url}/api/deploy/#{id}/files"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :get, url: url, headers: headers)
  end

  # todo: use execute() to support @dry_run?
  def upload_file(id,path,destination=nil)
    url = "#{@base_url}/api/deploy/#{id}/files"
    if !destination.empty?
      url += "/#{destination}"
    end
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream' }
    opts = { method: :post, url: url, headers: headers, payload: File.new(path,'rb')}
    if @dry_run
      return opts
    end
    uri = URI.parse(url)
    req = Net::HTTP::Post::Multipart.new uri.path,
    "file" => UploadIO.new(File.new(path,'rb'), "image/jpeg", File.basename(path))
    # todo: iterate headers and abstract th :upload_io to execute() too.
    req['Authorization'] = "Bearer #{@access_token}"
    res = Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(req)
    end
    res
  end

  def destroy(id)
    url = "#{@base_url}/api/deploy/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def deploy(id, options)
    url = "#{@base_url}/api/deploy/#{id}/deploy"
    payload = options
    if !options[:appDeploy].nil?
      if !options[:appDeploy][:config].nil?
        options[:appDeploy][:config] = options[:appDeploy][:config].to_json
      end
    end
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, timeout: nil, payload: payload.to_json)
  end
end
