require 'morpheus_test'

class MorpheusTest::ClientsTest < MorpheusTest::TestCase
  
  def test_clients_list
    assert_execute %(clients list)
    assert_execute %(clients list "System Admin")
  end

  # def test_clients_get_system_admin
  #   assert_execute %(clients get "System Admin")
  #   assert_execute %(clients get "System Admin" --permissions)
  # end

  def test_clients_get
    record = client.clients.list({})['clients'][0]
    if record
      assert_execute %(clients get "#{record['id']}")
      name_arg = record['clientId']
      assert_execute %(clients get "#{escape_arg name_arg}")
    else
      puts "No client found, unable to execute test `#{__method__}`"
    end
  end

  def test_clients_get_morph_cli
    assert_execute %(clients get morph-cli)
  end

  # todo: test all the other commands

  # def test_clients_add
  #   assert_execute %(clients add "test_client_#{random_id}" -N)
  # end

  # def test_clients_update
  #   #skip "Test needs to be added"
  #   assert_execute %(clients update "test_client_#{random_id}" --description "neat")
  # end

  # def test_clients_remove
  #   assert_execute %(clients remove "test_client_#{random_id}" -y")
  # end

end