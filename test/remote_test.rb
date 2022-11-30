require 'test_helper'

# Tests for Morpheus::Cli::Remote
class RemoteTest < TestCase  

  def requires_remote
    false
  end

  def requires_authentication
    false
  end

  def setup
    super()
    @@test_remote_name ||= "test_remote_#{SecureRandom.hex(10)}"
  end

  def teardown
    # switch back aftwards
    assert_execute %(remote use "#{escape_arg @config[:remote_name]}")
  end

  def test_remote_add
    assert_execute %(remote add "#{@@test_remote_name}" "#{escape_arg @config[:url]}" --insecure --use -N)
  end

  def test_remote_list
    assert_execute %(remote list)
    assert_execute %(remote list "#{@@test_remote_name}")
  end

  def test_remote_get
    assert_execute %(remote get)
    assert_execute %(remote get current)
    assert_execute %(remote get "#{@@test_remote_name}")
    assert_execute %(remote get "#{@@test_remote_name}" --offline)
  end

  def test_remote_current
    assert_execute %(remote current)
  end

  def test_remote_check
    assert_execute %(remote check)
    assert_execute %(remote check "#{@@test_remote_name}")
  end

  def test_remote_check_all
    assert_execute %(remote check-all)
  end

  def test_remote_update
    assert_execute %(remote update "#{@@test_remote_name}" --url "#{escape_arg @config[:url]}" --insecure)
    #assert_execute %(remote update "#{@@test_remote_name}" --name "#{@@test_remote_name}_updated")
    #assert_execute %(remote update "#{@@test_remote_name}_updated" --name "#{@@test_remote_name}")
  end

  def test_remote_rename
    assert_execute %(remote rename "#{@@test_remote_name}" "#{@@test_remote_name}_renamed" -y)
    assert_execute %(remote rename "#{@@test_remote_name}_renamed" "#{@@test_remote_name}" -y)
  end

  def test_remote_use
    assert_error %(remote use)
    assert_error %(remote use unknown_remote)
    assert_execute %(remote use "#{@@test_remote_name}")
    assert_execute %(remote use "#{@@test_remote_name}")
    assert_execute %(remote get current)
    assert_execute %(remote unuse)
    assert_error %(remote get current)
    assert_execute %(remote use "#{@@test_remote_name}"  -q)
  end

  def test_remote_remove
    assert_execute %(remote remove "#{@@test_remote_name}" -y)
  end

end