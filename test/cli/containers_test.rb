require 'morpheus_test'
require 'test_data_helper'

# Tests for Morpheus::Cli::Containers
class MorpheusTest::ContainersTest < MorpheusTest::TestCase
  
  include MorpheusTest::TestDataHelper  

  def setup()
    super
    #load_container_test_data()
  end

  def test_containers_get
    id = find_first_container_id()
    assert_execute %(containers get #{id})
  end

  # todo: need to wait and refresh status for this to work well
  
=begin
  def test_containers_get_many
    ids = find_many_container_ids().take(5)
    assert_execute %(containers get #{ids.join(' ')})
  end

  def test_containers_stop
    with_input ["n", "y"] do
      assert_execute %(containers stop #{@id}), exit_code: 9
      assert_execute %(containers stop #{@id})
    end
  end

  def test_containers_start
    with_input ["n", "y"] do
      assert_execute %(containers start #{@id}), exit_code: 9
      assert_execute %(containers start #{@id})
    end
  end

  def test_containers_restart
    with_input ["n", "y"] do
      assert_execute %(containers restart #{@id}), exit_code: 9
      assert_execute %(containers restart #{@id})
    end
  end

  def test_containers_suspend
    with_input ["n", "y"] do
      assert_execute %(containers suspend #{@id}), exit_code: 9
      assert_execute %(containers suspend #{@id})
    end
  end

  def test_containers_eject
    with_input ["n", "y"] do
      assert_execute %(containers eject #{@id}), exit_code: 9
      assert_execute %(containers eject #{@id})
    end
  end
=end

  def test_containers_actions
    @id = find_first_container_id()
    assert_execute %(containers actions #{@id})
  end

=begin
  # do not run random actions for now
  # def test_containers_action
  #   #action_code = "docker-remove-node"
  #   action = client.containers.available_actions(@id)['actions'].first
  #   assert action.is_a?(Hash),  "Expected to find an action to run"
  #   action_code = action['code']
  #   assert_execute %(containers action #{@id} -a #{action_code} -y)
  # end

  def test_containers_import
    with_input ["n", "y"] do
      assert_execute %(containers import #{@id} -N), exit_code: 9
      assert_execute %(containers import #{@id} -N)
    end
  end

  def test_containers_clone_image
    with_input ["n", "y"] do
      assert_execute %(containers clone-image #{@id} -N), exit_code: 9
      assert_execute %(containers clone-image #{@id} -N)
    end
  end
=end
end