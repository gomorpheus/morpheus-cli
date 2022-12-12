require 'test/unit'
require 'test_case'
require 'test_data_helper'

# setup at_start hook that runs once at the beginning of all tests
Test::Unit.at_start {
  
}

# setup at_exit hook that runs once at the end of all tests
Test::Unit.at_exit {
  # always logout when all done
  # logout_if_needed()
  # terminal.execute("logout") if is_logged_in()
  Morpheus::Terminal.instance.execute("logout")
}
