require 'test_helper'

class InstancesTest < TestCase
  
  # Tests for Morpheus::Cli::Instances
  # only list and get for now...
  def test_instances_list
    assert_execute %(instances list)
  end

  def test_instances_get
    instance = api_client.instances.list({})['instances'][0]
    if instance
      assert_execute %(instances get "#{instance['id']}")
      assert_execute %(instances get "#{escape_arg instance['name']}")
    else
      puts "No instance found, unable to test get command"
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

  # Tests for Morpheus::InstancesInterface api interface class
  def test_instances_interface
    @instances_interface = api_client.instances
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

  protected

  # def load_test_instance()
  #   instance_name = ENV['TEST_INSTANCE_NAME']
  #   if instance_name
  #     instances = api_client.list({name: instance_name})['instances']
  #     if instances.empty?
  #       puts "Test instance not found by name '#{instance_name}'"
  #     else
  #       instance = instances[0]
  #       if instance['name'] != instance_name
  #         assert_equal instance['name'], instance_name
  #         abort("Found the wrong instance!")
  #         return nil
  #       end
  #     end
  #     return instance
  #   else
  #     #puts "Skipping test because there is no test instance to load. You can set TEST_INSTANCE_NAME to enable this test"
  #     #return nil
  #     return load_first_instance()
  #   end
  # end

  # def load_first_instance()
  #   api_client.instances.list({})['instances'][0]
  # end

end