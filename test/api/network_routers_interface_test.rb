require 'morpheus_test'

# Tests for Morpheus::InstancesInterface
class MorpheusTest::NetworkRoutersInterfaceTest < MorpheusTest::TestCase
  
  def test_network_routers_interface
    @network_routers_interface = client.network_routers
    response = @network_routers_interface.list()
    network_routers = response['networkRouters']
    assert network_routers.is_a?(Array)
    if !network_routers.empty?
      response = @network_routers_interface.get(network_routers[0]['id'])
      network_router = response['networkRouter']
      assert network_router.is_a?(Hash)
      assert_equal network_router['id'], network_routers[0]['id']
    else
      #puts "No network routers found in this environment"
    end
    #todo: create and delete  
  end

end