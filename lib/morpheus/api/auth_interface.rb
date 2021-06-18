require 'morpheus/api/api_client'

class Morpheus::AuthInterface < Morpheus::APIClient

  # no Authorization header is required
  def authorization_required?
    false
  end

  def login(username, password, use_client_id=nil)
    if use_client_id
      self.client_id = use_client_id
    end
    @access_token, @refresh_token, @expires_at = nil, nil, nil
    url = "#{@base_url}/oauth/token"
    params = {grant_type: 'password', scope:'write', client_id: self.client_id, username: username}
    payload = {password: password}
    headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
    opts = {method: :post, url: url, headers: headers, params: params, payload: payload, timeout: 5}
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
  def use_refresh_token(refresh_token, use_client_id=nil)
    if use_client_id
      self.client_id = use_client_id
    end
    @access_token = nil
    url = "#{@base_url}/oauth/token"
    params = {grant_type: 'refresh_token', scope:'write', client_id: self.client_id}
    payload = {refresh_token: refresh_token}
    headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
    opts = {method: :post, url: url, headers: headers, params: params, payload: payload, timeout: 5}
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
