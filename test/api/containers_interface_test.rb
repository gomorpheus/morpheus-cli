require 'morpheus_test'

# Tests for Morpheus::ContainersInterface
class MorpheusTest::ContainersInterfaceTest < MorpheusTest::TestCase

  include MorpheusTest::TestDataHelper  

  def setup()
    super
    #load_container_test_data()
  end

  def test_get
    container_id = find_first_container_id()
    response = client.containers.get(container_id)
    assert response['container'].is_a?(Hash)
    assert_equal response['container']['id'], container_id
  end

  # todo: need to wait and refresh status for this to work well
  
=begin  
  def test_stop
    response = client.containers.stop(@id, {})
    assert_equal response['success'], true
  end

  def test_start
    response = client.containers.start(@id, {})
    assert_equal response['success'], true
  end

  def test_restart
    response = client.containers.restart(@id, {})
    assert_equal response['success'], true
  end

  def test_suspend
    response = client.containers.suspend(@id, {})
    assert_equal response['success'], true
  end

  def test_eject
    response = client.containers.eject(@id, {})
    assert_equal response['success'], true
  end

  def test_available_actions
    response = client.containers.available_actions(@id)
    assert response['actions'].is_a?(Array)
  end

  def test_action
    response = client.containers.action(@id, {})
    assert_equal response['success'], true
  end

  def test_import
    response = client.containers.import(@id, {})
    assert_equal response['success'], true
  end

  def test_clone_image
    response = client.containers.clone_image(@id, {})
    assert_equal response['success'], true
  end
=end
end