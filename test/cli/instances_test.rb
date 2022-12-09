require 'morpheus_test'

class MorpheusTest::InstancesTest < MorpheusTest::TestCase
  
  # Tests for Morpheus::Cli::Instances
  # only list and get for now...
  def test_instances_list
    assert_execute %(instances list)
  end

  def test_instances_get
    instance = client.instances.list({})['instances'][0]
    if instance
      assert_execute %(instances get "#{instance['id']}")
      assert_execute %(instances get "#{escape_arg instance['name']}")
    else
      puts "No instance found, unable to execute test `#{__method__}`"
    end
  end

  # def test_instances_add
  #   warn "Skipped test test_instances_add() because it is not implemented"
  # end

  # def test_instances_update
  #   warn "Skipped test test_instances_update() because it is not implemented"
  # end

  # def test_instances_delete
  #   warn "Skipped test test_instances_remove() because it is not implemented"
  # end

  # todo: many more instance commands to add

  protected

end