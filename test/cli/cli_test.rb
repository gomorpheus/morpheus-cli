require 'morpheus_test'

# Tests for top level CLI functionality
class MorpheusTest::CliTest < MorpheusTest::TestCase
  
  def requires_remote
    false
  end

  def requires_authentication
    false
  end

  def test_cli_no_arguments
  	assert_error("")
  end

  def test_cli_unknown_command
    assert_error("unknown_command")
  end

  def test_cli_unknown_subcommand
    assert_error("instances unknown_subcommand")
  end

  def test_cli_version_option
    assert_execute("-v")
    assert_execute("--version")
  end

  # HelpTest handles this now..
  # def test_help
  #   assert_execute("help")
  # 	assert_execute("-h")
  # 	assert_execute("--help")
  # end

end