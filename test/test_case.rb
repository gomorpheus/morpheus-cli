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
    @config = get_config()
    # use the remote and login
    use_remote() if requires_remote
    login_if_needed() if requires_authentication
  end

  # hook at the end of each test
  def teardown()
    #puts "TestCase #{self} teardown()"
    #logout_if_needed() if requires_authentication
  end

end

