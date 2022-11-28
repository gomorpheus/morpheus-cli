require 'test_helper'

class WhoamiTest < TestCase
  
  def test_whoami
    assert_execute("whoami")
  end

  def test_whoami_401
    without_authentication do
      assert_error("whoami", {failure: "Expected 401 error while unauthorized"})
    end
  end

end