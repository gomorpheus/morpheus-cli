require 'morpheus_test'

class MorpheusTest::ShellTest < MorpheusTest::TestCase

  def requires_remote
    false
  end

  def requires_authentication
    false
  end

  # class << self
  #   def startup
  #     # one time use remote and login at beginning of testsuite, not each method
  #     use_remote()
  #     login()
  #   end
  # end

  # def test_remote_use
  #   # use remote needed for all except test_shell_clean() , todo: exclude paradigm that yet..
  #   use_remote()
  # end

  def test_shell
    with_input "exit"  do
      assert_execute "shell"
    end
  end

  def test_shell_verbose
    login_if_needed()
    with_input "whoami", "exit" do
      assert_execute "shell -V"
    end
  end

  def test_shell_history
    with_input "history", "exit" do
      assert_execute "shell"
    end
  end

  def test_shell_sleep
    with_input "echo \"It is time for a rest.\"", "sleep 0.5", "echo \"OK, let's keep testing\"", "exit" do
      assert_execute "shell -V"
    end
  end

  def test_shell_temporary
    with_input "remote list", "remote current", "echo this is a temporary shell with no history", "history", "exit" do
      assert_execute "shell -Z -V"
    end
  end

  def test_shell_confirmation
    with_input "access-token refresh", "I'm not sure...", "no", "exit" do
      assert_execute "shell -Z -V"
    end
  end

# todo: fix bug where appliances are not restored after clean shell.. so remote use #{@config.remote_name}" starts failing here..
=begin
  def test_shell_clean
    with_input "echo this is a clean shell with no remotes or history", "remote list", "remote current", "history", "exit" do
      assert_execute "shell -z"
    end
    with_input "echo this is another clean shell", "exit" do
      assert_execute "shell --clean"
    end
  end

  def test_shell_history_again
    with_input "echo back in test shell again with our remote and history", "remote get #{@config.remote_name}", "history", "exit" do
      assert_execute "shell"
    end
  end
=end

end