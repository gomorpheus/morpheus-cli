require 'test_helper'

# Tests for login and logout
class AuthTest < TestCase
  
  def requires_authentication
    false
  end

  def test_login
    assert_execute %(login "#{escape_arg @config[:username]}" "#{escape_arg @config[:password]}")
    assert is_logged_in()
  end

  def test_login_bad_credentials
    assert_error %(login "#{escape_arg @config[:username]}" "invalid_password")
    assert !is_logged_in()
  end

  def test_login_test_option
    without_authentication do
      assert_equal(is_logged_in(), false, "begin as logged out")
      assert_execute(%(login --test "#{escape_arg @config[:username]}" "#{escape_arg @config[:password]}"))
      assert_equal(is_logged_in(), false, "should still be logged out")
    end

    with_authentication do
      assert is_logged_in()
      assert_error %(login --test "#{escape_arg @config[:username]}" "invalid_password")
      assert is_logged_in(), "should still be logged in"
    end
  end

  def test_logout
    with_authentication do
      assert_execute %(logout)
      assert !is_logged_in()
    end
    without_authentication do
      assert_execute %(logout)
      assert !is_logged_in()
    end
  end

  def test_login_prompt
    with_input @config[:username].to_s, @config[:password] do
      assert_execute %(login)
    end
    with_input @config[:username].to_s, "invalid_password" do
      assert_error %(login --test)
    end
    without_authentication do
      with_input @config[:username], @config[:password] do
        assert_execute %(instances list)
      end
    end
  end

  def test_login_adhoc
    assert_execute %(login "#{escape_arg @config[:username]}" "#{escape_arg @config[:password]}")
    assert is_logged_in()
    assert_execute %(login "#{escape_arg @config[:username]}" "#{escape_arg @config[:password]}")
    assert is_logged_in()
    assert_execute("logout")
    assert !is_logged_in()

    # a bit meta, but let's test our helper methods here..
    # login()
    # assert_equal(is_logged_in(), true, "should be logged in")
    # logout()
    # assert_equal(is_logged_in(), false, "should be logged out")
    # login_if_needed()
    # assert_equal(is_logged_in(), true, "should be logged in")
    # logout_if_needed()
    # assert_equal(is_logged_in(), false, "should be logged out")
    # logout()
    # assert_equal(is_logged_in(), false, "should be logged out")
    # login_if_needed()
    # assert_equal(is_logged_in(), true, "should be logged in")
  end

end