require 'morpheus_test'

# Tests for Morpheus::WhoamiInterface
class MorpheusTest::WhoamiInterfaceTest < MorpheusTest::TestCase
  
  def test_whoami_interface
    @whoami_interface = client.whoami
    response = @whoami_interface.get()
    assert_equal response['user']['username'], @config.username
    # todo: fix this, can be cached and fail
    #assert_equal response['appliance']['buildVersion'], Morpheus::Cli::Remote.load_remote(@config.remote_name)[:build_version]
  end

end