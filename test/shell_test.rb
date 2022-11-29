require 'test_helper'

class ShellTest < TestCase

  #todo: I think terminal.execute("") is not working after shell is forked...
  # maybe need to use Shell.instance.execute("exit") instead..heh

  # def test_shell
  #   assert_execute("shell")
  #   assert_execute("exit")
  # end

  # def test_shell_temporary
  #   assert_execute("shell -Z")
  #   assert_execute("remote current")
  #   assert_execute("exit")
  # end

  # def test_shell_verbose
  #   assert_execute("shell -V")
  #   assert_execute("remote current")
  #   assert_execute("exit")
  # end

end