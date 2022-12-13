module MorpheusTest

  # Mixin to provide loading test data / fixtures for tests
  module TestDataHelper

    def self.included(base)
      #base.extend ClassMethods
      #todo: load test/fixtures/*yaml
    end

    protected

    ## Instances

    def find_first_instance_id()
      instance_id = client.instances.list({})['instances'].collect {|it| it['id'] }.first
      assert_not_nil instance_id, "Failed to find an instance to test with"
      return instance_id
    end

    def find_many_instance_ids()
      instance_ids = client.instances.list({})['instances'].collect {|it| it['id'] }.first(5)
      assert instance_ids.size > 1, "Failed to find many instances to test with"
      return instance_ids
    end

    # populates test with the following data as instance variables
    # @container - Container
    # @id - Container id
    #todo: create a container instead...
    # maybe just warn and omit the test, but it asserts and fails  now...
    # instead of env, have a test/fixtures/test-instance-payload.json or
    # or maybe put it in the test_config.yaml under fixtures.
    def load_instance_test_data()
      # todo: cache this , maybe Thread.current for now...
      @id = nil

      test_instance_id = ENV['TEST_INSTANCE_ID']
      if test_instance_id
        # use the first container in our test instance
        @instance = client.instances.get(test_instance_id.to_i)['instance']
        # rescue ::RestClient::Exception => e  on 404
        assert_not_nil @instance, "Test instance #{test_instance_id} was not found!"
        @container = client.containers.get(@instance['containers'].first)['container']
        @id = @instance['id']
      end
      assert_not_nil @id, "A test instance must be specified to run this test.\nTry setting environment variable TEST_CONTAINER_ID=42 or TEST_INSTANCE_ID=99"
    end
  
    ## Containers

    def find_first_container_id()
      container_id = client.instances.list({})['instances'].collect {|it| it['containers'] }.flatten.uniq.first
      assert_not_nil container_id, "Failed to find a container to test with"
      return container_id
    end

    def find_many_container_ids()
      container_ids = client.instances.list({})['instances'].collect {|it| it['containers'] }.flatten.uniq.first(5)
      assert container_ids.size > 1, "Failed to find many containers to test with"
      return container_ids
    end

    # populates test with the following data as instance variables
    # @container - Container
    # @id - Container id
    #todo: create a container instead...
    # maybe just warn and omit the test, but it asserts and fails  now...
    # instead of env, have a test/fixtures/test-instance-payload.json or
    # or maybe put it in the test_config.yaml under fixtures.
    def load_container_test_data()
      # todo: cache this , maybe Thread.current for now...
      @id = nil
      test_container_id = ENV['TEST_CONTAINER_ID']
      test_instance_id = ENV['TEST_INSTANCE_ID']
      if test_container_id
        # use our test container
        @container = client.containers.get(test_container_id)['container']
        # rescue ::RestClient::Exception => e  on 404
        assert_not_nil @container, "Container #{test_container_id} was not found"
        @id = @container['id']
      elsif test_instance_id
        # use the first container in our test instance
        @instance = client.instances.get(test_instance_id.to_i)['instance']
        # rescue ::RestClient::Exception => e  on 404
        assert_not_nil @instance, "Test instance #{test_instance_id} was not found!"
        assert_not_nil @instance['containers'].first, "Instance #{@instance['id']} does not have any containers\nTry setting environment variable TEST_CONTAINER_ID=42"
        @container = client.containers.get(@instance['containers'].first)['container']
        assert_not_nil @container, "Container #{@instance['containers'].first} was not found"
        @id = @container['id']
      end
      assert_not_nil @id, "A test container must be specified to run this test.\nTry setting environment variable TEST_CONTAINER_ID=42 or TEST_INSTANCE_ID=99"
    end
  
  end

end