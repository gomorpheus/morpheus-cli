require 'morpheus_test'

# Tests for Morpheus::InstancesInterface
class MorpheusTest::InstancesInterfaceTest < MorpheusTest::TestCase
  
  def test_instances_interface
    @instances_interface = client.instances
    response = @instances_interface.list()
    instances = response['instances']
    assert instances.is_a?(Array)
    if !instances.empty?
      response = @instances_interface.get(instances[0]['id'])
      instance = response['instance']
      assert instance.is_a?(Hash)
      assert_equal instance['id'], instances[0]['id']
    else
      #puts "No instances found in this environment"
    end
    #todo: create and delete  
  end

end