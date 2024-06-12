require 'morpheus_test'

# Tests for Morpheus::Cli::NetworkRouters
class MorpheusTest::NetworkRoutersTest < MorpheusTest::TestCase

  def test_network_routers_list
    assert_execute %(network-routers list)
  end

  def test_network_routers_get
    network_router = client.network_routers.list({})['networkRouters'][0]
    if network_router
      assert_execute %(network-routers get "#{network_router['id']}")
      assert_execute %(network-routers get "#{escape_arg network_router['name']}")
    else
      puts "No network routers found, unable to execute test `#{__method__}`"
    end
  end

  def test_network_routers_firewall_rules
    network_router = client.network_routers.list({})['networkRouters'].find {|it| it['firewall'] }
    if network_router
      assert_execute %(network-routers firewall-rules "#{network_router['id']}")
    else
      puts "No network routers found with a firewall, unable to execute test `#{__method__}`"
    end
  end

  def test_network_routers_firewall_rules_get
    network_router = client.network_routers.list({})['networkRouters'].find {|it| it['firewall'] }
    if network_router
      # need to get by id to get the firewall rules
      network_router = client.network_routers.get(network_router['id'])['networkRouter']
      rules = network_router['type']['hasFirewallGroups'] ? (network_router['firewall']['ruleGroups'] || []).collect {|it| it['rules']}.flatten : network_router['firewall']['rules']
      rule = rules[0]
      if rule
        assert_execute %(network-routers firewall-rule "#{network_router['id']}" "#{rule['id']}")
      else
        puts "No network router firewall rules found, unable to execute test `#{__method__}`"
      end
    else
      puts "No network routers found with a firewall, unable to execute test `#{__method__}`"
    end
  end

  # def test_network_routers_add
  #   warn "Skipped test test_network_routers_add() because it is not implemented"
  # end

  # def test_network_routers_update
  #   warn "Skipped test test_network_routers_update() because it is not implemented"
  # end

  # def test_network_routers_delete
  #   warn "Skipped test test_network_routers_remove() because it is not implemented"
  # end

  # todo: many more network-routers commands to add

  protected

end