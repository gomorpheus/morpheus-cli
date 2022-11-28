require 'test_helper'

# Tests for Morpheus::Cli::AccessTokenCommand
class AccessTokenTest < TestCase
  
  def test_access_token
    assert_execute("access-token")
    assert_execute("access-token get")
    assert_equal(is_logged_in(), true, "is_logged_in() should be true after access-token refresh")
  end

  def test_access_token_details
    assert_execute("access-token details")
  end

  def test_access_token_refresh
    previous_token = get_access_token()
    without_authentication do 
      login()
      assert_execute("access-token refresh -y")
      assert_equal(is_logged_in(), true, "is_logged_in() should be true after access-token refresh")
      new_token = get_access_token()
      assert_not_equal(previous_token, new_token, "Access token should have changed")
      assert_error("login --test --token #{previous_token} ", "Old token should no longer be valid after refresh")
      assert_execute("login --token #{new_token} ", "New token should be valid after refresh")
    end
  end

  def test_access_token_unauthenticated
    without_authentication do 
      assert_error("access-token")
      assert_error("access-token get")
    end
  end

end