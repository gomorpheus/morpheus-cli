require 'test_helper'

# Tests for login and logout
class AuthTest < TestCase
  
  def requires_authentication
    false
  end

  def test_login
    assert_execute("login '#{@config[:username]}' '#{@config[:password]}'")
    assert_equal(is_logged_in(), true, "is_logged_in() should be true after login()")
  end

  def test_login_bad_credentials
    assert_error("login '#{@config[:username]}' 'invalid-password'", "Expected bad credentials error")
    assert_equal(is_logged_in(), false, "is_logged_in() should be false after failed login")
  end

  def test_login_test_option
    without_authentication do
      assert_equal(is_logged_in(), false, "begin as logged out")
      assert_execute("login --test '#{@config[:username]}' '#{@config[:password]}'")
      assert_equal(is_logged_in(), false, "should still be logged out")
    end

    with_authentication do
      assert_equal(is_logged_in(), true, "begin as logged in")
      assert_error("login --test '#{@config[:username]}' 'invalid-password'", "Expected bad credentials error")
      assert_equal(is_logged_in(), true, "should still be logged in")
    end
  end

  def test_logout
    with_authentication do
      assert_execute("logout")
      assert_equal(is_logged_in(), false, "is_logged_in() should be false after logout()")
    end
    without_authentication do
      assert_execute("logout")
      assert_equal(is_logged_in(), false, "is_logged_in() should be false after logout()")
    end
  end

  def test_login_adhoc
    assert_execute("login '#{@config[:username]}' '#{@config[:password]}'")
    assert_equal(is_logged_in(), true, "is_logged_in() should be true after login()")
    assert_execute("login '#{@config[:username]}' '#{@config[:password]}'")
    assert_equal(is_logged_in(), true, "is_logged_in() should be true after login()")
    assert_execute("logout")
    assert_equal(is_logged_in(), false, "is_logged_in() should be true after logout()")

    # a bit meta, but let's test our helper methods here..
    login()
    assert_equal(is_logged_in(), true, "is_logged_in() should be true after login()")
    login_if_needed()
    assert_equal(is_logged_in(), true, "is_logged_in() should be true after login_if_needed()")
    logout_if_needed()
    assert_equal(is_logged_in(), false, "is_logged_in() should be true after logout_if_needed()")
    logout()
    assert_equal(is_logged_in(), false, "is_logged_in() should be true after logout()")
  end

end