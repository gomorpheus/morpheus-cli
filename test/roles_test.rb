require 'test_helper'

class RolesTest < TestCase
  
  def test_roles_list
    assert_execute %(roles list)
    assert_execute %(roles list "System Admin")
  end

  def test_roles_get
    assert_execute %(roles get "System Admin")
    assert_execute %(roles get "System Admin" --permissions)
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