require 'morpheus/api/api_client'

class Morpheus::AuthInterface < Morpheus::APIClient

  #attr_reader :access_token, :refresh_token, :expires_at

  def initialize(base_url, access_token=nil)
    @base_url = base_url
    @access_token = access_token
  end

  def login(username, password)
    @access_token, @refresh_token, @expires_at = nil, nil, nil
    url = "#{@base_url}/oauth/token"
    params = {grant_type: 'password', scope:'write', client_id: 'morph-cli', username: username}
    payload = {password: password}
    opts = {method: :post, url: url, headers:{ params: params}, payload: payload, timeout: 5}
    response = execute(opts)
    return response if @dry_run
    @access_token = response['access_token']
    @refresh_token = response['refresh_token']
    if response['expires_in'] != nil
      @expires_at = Time.now + response['expires_in']
    end
    return response
  end

  # this regenerates the access_token and refresh_token
  def use_refresh_token(refresh_token)
    @access_token = nil
    url = "#{@base_url}/oauth/token"
    params = {grant_type: 'refresh_token', scope:'write', client_id: 'morph-cli'}
    payload = {refresh_token: refresh_token}
    opts = {method: :post, url: url, headers:{ params: params}, payload: payload}
    response = execute(opts)
    return response if @dry_run
    @access_token = response['access_token']
    @refresh_token = response['refresh_token']
    if response['expires_in'] != nil
      @expires_at = Time.now + response['expires_in']
    end
    return response
  end

  def logout()
    # super.logout()
    if @access_token
      # todo: expire the token
    end
    raise "#{self}.logout() is not yet implemented"
  end
end
