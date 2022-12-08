require 'test/unit'
require 'securerandom'

# Base TestCase for CLI unit tests to provide standard behavior
# Most of the test environment configuration is done in test_helper.rb
class TestCase < Test::Unit::TestCase

  # execute test cases in the order they are defined.
  self.test_order = :defined

  #todo: move config parsing and establishing test environment and terminal from helper to here..

  # indicates the test requires the user to have a current remote
  # override this to return false if your tests do not require `remote use` as part of its setup
  def requires_remote
    true
  end

  # indicates the test requires the user to be logged in and authenticated
  # override this to return false if your tests do not require `login` as part of its setup
  def requires_authentication
    true
  end

  # hook at the beginning of each test
  def setup()
    #puts "TestCase #{self} setup()"
    # @config is provided for accessing test environment settings in our tests
    @config = get_config()
    # use the remote and login if needed
    use_remote() if requires_remote
    login_if_needed() if requires_authentication
  end

  # @return [Morpheus::APIClient] client for executing api requests in our tests and examining the results
  def api_client
    # todo: return terminal.get_api_client()
    #@api_client ||= Morpheus::APIClient.new(url: @config[:url], username: @config[:username], password: @config[:password], verify_ssl: false, client_id: 'morph-api')
    #@api_client.login() unless @api_client.logged_in?
    # this only works while logged in, fine for now...
    @api_client ||= Morpheus::APIClient.new(url: @config[:url], username: @config[:username], access_token: get_access_token(), verify_ssl: false, client_id: 'morph-cli')
  end

  # hook at the end of each test
  def teardown()
    #puts "TestCase #{self} teardown()"
    #logout_if_needed() if requires_authentication
  end

end

