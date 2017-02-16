class Morpheus::AuthInterface < Morpheus::APIClient

  attr_reader :access_token

  def initialize(base_url, access_token=nil)
    @base_url = base_url
    @access_token = access_token
  end

  def login(username, password)
    @access_token = nil
    url = "#{@base_url}/oauth/token"
    params = {grant_type: 'password', scope:'write', client_id: 'morph-cli', username: username}
    payload = {password: password}
    response = Morpheus::RestClient.execute(method: :post, url: url, 
                            headers:{ params: params}, payload: payload, timeout: 10)
    json = JSON.parse(response.to_s)
    @access_token = json['access_token']
    return json
  end

  def logout()
    if @access_token
      # todo: expire the token
    end
    raise "#{self}.logout() is not yet implemented"
  end
end
