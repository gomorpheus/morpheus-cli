require 'test_helper'

class ManTest < TestCase
  
  def test_man
    # need to use -q to avoid interactive right now...
    assert_execute("man -q")
    assert_execute("man -g -q")
    assert_execute("man -q")
    man_file_path = Morpheus::Cli::ManCommand.man_file_path
    assert(File.exist?(man_file_path), "File #{man_file_path} should have been created.")
  end

end