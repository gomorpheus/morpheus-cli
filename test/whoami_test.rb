require 'test_helper'

class WhoamiTest < TestCase
  
  def test_whoami
    assert_execute("whoami")
    assert_execute("whoami --name")
    assert_execute("whoami --permissions")
  end

  def test_whoami_unauthorized
    without_authentication do
      assert_error("whoami", "Expected error while unauthorized")
    end
  end

end