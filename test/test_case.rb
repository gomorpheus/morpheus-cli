require 'test/unit'
require 'securerandom'

# Base TestCase for CLI unit tests to provide standard behavior
# Most of the test environment configuration is done in test_helper.rb
class TestCase < Test::Unit::TestCase

  # execute test cases in the order they are defined.
  self.test_order = :defined

  #todo: move config parsing and establishing test environment and terminal from helper to here..

  # testcase_id provides a random id for the duration of the test run
  # @@testcase_id = nil

  # # testsuite_id provides a random id for the duration of all TestCase runs
  # @@testrun_id = nil

  # class << self
  #   # hook at beginning of tests tests in this class
  #   def startup
  #     #puts "TestCase #{self} startup()"
  #     @@testcase_id = SecureRandom.hex(10)
  #     @@testrun_id ||= SecureRandom.hex(10)
  #   end

  #   # hook that is run at the end of all tests in this class
  #   def shutdown
  #     #puts "TestCase #{self} shutdown()"
  #     @@testcase_id = nil
  #     @@testrun_id = nil
  #   end
  # end

  # indicates the test requires the user to have a current remote
  # override this to return false if your tests do not require `remote use` as part of its setup
  def requires_remote
    true
  end

  # indicates the test requires the user to be logged in and and authenticated
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

  # provides a random id for the duration of the all the tests methods being run for this TestCase
  # def testcase_id
  #   @@testcase_id
  # end

  # # provides a random id for the duration of the all the entire test run, for all TestCase classes
  # def testrun_id
  #   @@testrun_id
  # end

end

