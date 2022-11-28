require 'test_helper'

# Tests for help command and global --help option
class HelpTest < TestCase
  
  def requires_authentication
    false
  end

  def test_help
  	assert_execute %(help)
  	assert_execute %(-h)
  	assert_execute %(--help)
  end

  def test_subcommand_help
  	assert_execute %(remote --help)
  	assert_execute %(remote -h)
  	assert_execute %(remote use --help)
    assert_execute %(instances list --help)
  	assert_execute %(whoami --help)
  	assert_execute %(whoami -h)
  end

end