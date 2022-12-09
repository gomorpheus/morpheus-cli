require 'morpheus_test'

# Tests for Morpheus::Cli::View class, corresponds to the `view` CLI command
class MorpheusTest::ViewTest < MorpheusTest::TestCase
  
  def teardown
    # todo: close browser after each test
  end

# these all pass but it's kind of obnoxious to open so many tabs

=begin
  def test_view
    assert_execute %(view)
  end

  def test_view_login
    assert_execute %(view --login)
    #puts "pausing a moment while logging in with browser"
    #sleep(3)
    
  end

  def test_view_login_short
    assert_execute %(view -l)
    #puts "pausing a moment while logging in with browser"
    #sleep(3)
  end

  def test_view_clouds
    assert_execute %(view clouds)
  end

  def test_view_cloud_by_id
    cloud = client.clouds.list({})['zones'][0]
    if cloud
      assert_execute %(view cloud "#{escape_arg cloud['id']}")
    else
      puts "No cloud found, unable to execute test `#{__method__}`"
    end
  end

  def test_view_instance_by_name
    assert_execute %(view -l)
    instance = client.instances.list({})['instances'][0]
    if instance
      assert_execute %(view instance "#{escape_arg instance['name']}")
    else
      puts "No instance found, unable to execute test `#{__method__}`"
    end
  end
=end
  protected

end