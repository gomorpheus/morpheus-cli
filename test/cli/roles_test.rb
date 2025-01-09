require 'morpheus_test'

class MorpheusTest::RolesTest < MorpheusTest::TestCase
  
  def test_roles_list
    assert_execute %(roles list)
    assert_execute %(roles list "System Admin")
  end

  # def test_roles_get_system_admin
  #   assert_execute %(roles get "System Admin")
  #   assert_execute %(roles get "System Admin" --permissions)
  # end

  def test_roles_get
    # role = client.roles.list({})['roles'][0]
    role = client.roles.list({})['roles'].find {|r| r['authority'] !~ /\A\d+\Z/}
    if role
      assert_execute %(roles get "#{role['id']}")
      name_arg = role['authority']
      assert_execute %(roles get "#{escape_arg name_arg}")
      assert_execute %(roles get "#{escape_arg name_arg}" --permissions)
    else
      puts "No role found, unable to execute test `#{__method__}`"
    end
  end

  def test_roles_list_permissions
    assert_execute %(roles list-permissions "System Admin")
  end

  # todo: test all the other commands

  # def test_roles_add
  #   assert_execute %(roles add "test_role_#{random_id}" -N)
  # end

  # def test_roles_update
  #   #skip "Test needs to be added"
  #   assert_execute %(roles update "test_role_#{random_id}" --description "neat")
  # end

  # def test_roles_remove
  #   assert_execute %(roles remove "test_role_#{random_id}" -y")
  # end

end