require 'morpheus_test'

# Tests for Morpheus::Cli::Containers
class MorpheusTest::ContainersTest < MorpheusTest::TestCase
  
  def test_containers_get
    container_id = get_a_container_id()
    if container_id
      assert_execute %(containers get #{container_id})
    else
      puts "No container found, unable to execute test `#{__method__}`"
    end
  end


  def test_containers_get_many
    container_ids = get_many_container_ids()
    if container_ids.size > 1
      assert_execute %(containers get #{container_ids.join(' ')})
    else
      puts "More than one container not found, unable to execute test `#{__method__}`"
    end
  end

  def test_containers_actions
    container_id = get_a_container_id()
    if container_id
      assert_execute %(containers actions #{container_id})
    else
      puts "No container found, unable to execute test `#{__method__}`"
    end
  end


  def test_containers_actions_many
    container_ids = get_many_container_ids()
    if container_ids.size > 1
      assert_execute %(containers actions #{container_ids.first(2).join(' ')})
    else
      puts "More than one container not found, unable to execute test `#{__method__}`"
    end
  end

  # todo: many more containers commands to test

  protected

  def get_a_container_id()
    get_many_container_ids().first
  end

  def get_many_container_ids()
    container_ids = []
    client.instances.list({})['instances'].each do |instance|
      container_ids += instance['containers']
    end
    container_ids.uniq.first(5)
  end

end