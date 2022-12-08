# Provides setup of the environment for executing the CLI unit tests.
# This makes testing of command execution via the CLI terminal easy to write.
#
#
# ==== Examples
#
#   def test_whoami
#     assert_execute("whoami")
#   end
#
#   def test_unknown_command
#     assert_error("foobar")
#   end
#

# require dependencies
# using test-unit gem for unit tests
require 'test/unit'
# TestCase is the our base Test::Unit::TestCase
require 'test_case'

# use a different default home directory when running tests
# load settings from environment variables and config file
unless ENV['MORPHEUS_CLI_HOME']
  ENV['MORPHEUS_CLI_HOME'] = File.join(Dir.home, ".morpheus_test")
end

# load morpheus CLI library
#$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'morpheus'
#todo: Probably add tests for all modules, separating Morpheus::Cli and Morpheus::Api
# require 'morpheus/api'
# require 'morpheus/cli'
# PrintHelper for parse_json_or_yaml()
include Morpheus::Cli::PrintHelper


# setup at_exit hook that runs once at the end of all tests
Test::Unit.at_exit {
  #puts "Test Suite Complete"
  # always logout when all done
  logout_if_needed()
}

# Execute the command in the CLI terminal and assert the result
# By default, the result should be a success with exit code: 0 and error: nil
# @param [String] cmd the command or expression to be executed by the CLI terminal
# @param [Hash,String] opts. See +assert_command_result+ If passed as a String, then treated as failure message.
# @param [String] failure_message Optional message to use on failure used instead of the default "Expected command..."
#
# @example Assert a command succeeds with a 0 exit status
#   assert_execute("whoami")
#
# @example Assert that a command fails with any non zero exit status
#   assert_execute("foobar", success:false, "Expected unknown command to fail")
#
# @example Assert a specific exit status code
#   assert_execute("foobar", exit:1, "Expected unknown command to fail")
#
def assert_execute(cmd, opts = {}, failure_message = nil)
  opts = opts.is_a?(String) ? {failure_message:opts} : (opts || {})
  result = terminal.execute(cmd)
  assert_command_result(result, opts, failure_message)
end

# +assert_success()+ is an alias for +assert_execute()+
alias :assert_success :assert_execute

# Execute the command  in the CLI terminal and assert that the result is in an error (exit non-0)
# @param [String] cmd the command or expression to be executed by the CLI terminal
# @param [Hash,String] opts. See +assert_command_result+ If passed as a String, then treated as failure message.
# @param [String] failure_message Optional message to use on failure used instead of the default "Expected command to succeed|fail..."
#
# @example Assert a command fails with an error
#   assert_error("apps list --unknown-option", "Expected unknown option error")
#
def assert_error(cmd, opts = {}, failure_message = nil)
  opts = opts.is_a?(String) ? {failure_message:opts} : (opts || {})
  assert_execute(cmd, opts.merge(success:false), failure_message)
end

# Assert that a command is has the expected exit status and message
# The default behavior is to assert the result is successful, exit: 0, error: nil
# use {success:false} to assert non-zero
# or use {exit:1, error: "something bad happened"} to assert a specific error exit and/or message
# @param [Array] Result containing: [exit_code, error].
# @param [Hash,String] opts. Hash of options for assertion. If passed as a String, then treated as failure message.
# @option opts [true,false] :success Expect success (true) or failure (false). Default is +true+, set to +false+ to assert that an error occurs instead.
# @option opts [Integer] :exit Expect a specific exit status code. The default is 0 on success or anything but 0 for failure.
# @option opts [String] :failure Optional message to use on failure used instead of the default "Expected command to succe..."
# @param [String] failure_message Optional message to use on failure used instead of the default "Expected command to succeed|fail..."
def assert_command_result(result, opts = {}, failure_message = nil)
  # determine what to assert
  success = opts.key?(:success) ? opts[:success] : true
  expected_code = opts[:exit] ? opts[:exit] : (success ? 0 : nil)
  if expected_code && expected_code != 0
    success = false
  end
  expected_message = opts[:error]
  failure_message = failure_message || opts[:failure_message] || opts[:failure]
  # parse command result
  exit_code, err = Morpheus::Cli::CliRegistry.parse_command_result(result)
  # result assertions
  if success
    assert_equal([0, nil], [exit_code, err], failure_message || "Expected command to succeed with exit code: 0 and instead got exit code: #{exit_code.inspect}, error: #{err.inspect}")
  else
    if expected_code
      assert_equal(expected_code, exit_code, failure_message || "Expected command to fail with exit code: #{expected_code.inspect} and instead got exit code: #{exit_code.inspect}, error: #{err.inspect}")
    else
      assert_not_equal(0, exit_code, failure_message || "Expected command to fail with exit code: (non-zero) and instead got exit code: #{exit_code.inspect}, error: #{err.inspect}")
    end
    if expected_message
      assert_equal(expected_message, err, "Expected command to fail with error message: #{expected_message.inspect} and instead got error message: #{err.inspect}")
    end
  end
end

# Get the shared CLI terminal
# @return [Morpheus::Terminal]
def terminal
  # return Morpheus::Terminal.instance
  establish_test_terminal()
  Thread.current[:terminal]
end

# Get the shared test configuration settings
# parses environment variables and config file to establish CLI environment
# @return [Map] containing :url, :username, etc., including :password!
def get_config(refresh=false)
  if Thread.current[:config].nil?
    Thread.current[:config] = {}
    config = Thread.current[:config]
    # load settings from environment variables and config file
    config[:homedir] = Morpheus::Cli.home_directory #ENV['TEST_HOME'] || File.join(Dir.home, ".morpheus_test")
    config[:remote_name] = ENV['TEST_REMOTE_NAME'] || 'unit_test'
    config[:url] = ENV['TEST_REMOTE_URL'] || ENV['TEST_URL'] # || 'http://localhost:8080'
    config[:username] = ENV['TEST_USERNAME']
    config[:password] = ENV['TEST_PASSWORD']
     # needs to create file to append to... meh just let shell handle it..
    # config[:stdout] = ENV['TEST_STDOUT']
    # config[:stderr] = ENV['TEST_STDERR']
    # config[:stdin] = ENV['TEST_STDIN']
    config[:debug] = ENV['TEST_DEBUG'].to_s.strip.downcase == "true" || ENV['DEBUG'].to_s.strip.downcase == "true"
    # config[:temporary] = ENV['TEST_TEMPORARY'].to_s.strip.downcase == "true"
    # config[:quiet] = ENV['TEST_QUIET'].to_s.strip.downcase == "true"
    config_filename = nil
    if ENV['TEST_CONFIG']
      config_filename = ENV['TEST_CONFIG']
    elsif File.exist?("test_config.yaml")
      config_filename = "test_config.yaml"
    elsif File.exist?(File.join(config[:homedir], "test_config.yaml"))
      config_filename = File.join(config[:homedir], "test_config.yaml")
    end
    if config_filename
      full_filename = File.expand_path(config_filename)
      file_content = nil
      if File.exist?(full_filename)
        file_content = File.read(full_filename)
      else
        abort("Test config file not found: #{full_filename}")
      end
      parse_result = parse_json_or_yaml(file_content)
      config_map = parse_result[:data]
      if config_map.nil?
        abort("Failed to parse test config file '#{config_filename}' as YAML or JSON. Error: #{parse_result[:error]}")
      end
      config[:homedir] = config_map['homedir'] if config_map['homedir']
      config[:remote_name] = config_map['remote_name'] if config_map['remote_name']
      config[:url] = (config_map['url'] || config_map['remote_url']) if (config_map['url'] || config_map['remote_url'])
      config[:username] = config_map['username'] if config_map['username']
      config[:password] = config_map['password'] if config_map['password']
      # config[:stdout] = config_map['stdout'] if config_map['stdout']
      # config[:stderr] = config_map['stderr'] if config_map['stderr']
      # config[:stdin] = config_map['stdin'] if config_map['stdin']
      config[:debug] = config_map['debug'].to_s.strip.downcase == "true" if config_map.key?('debug')
      # config[:quiet] = config_map['temporary'].to_s.strip.downcase == "true" if config_map.key?'temporary')
      # config[:temporary] = config_map['temporary'].to_s.strip.downcase == "true" if config_map.key?'temporary')
    end
    # For now force user to create a test_config.yaml or use environment variables
    if config[:remote_name].to_s.empty?
      abort("Unable to execute unit tests without specifying a remote name.\You must specify the environment variable TEST_REMOTE_NAME=unit_test\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nremote_name: unit_test\n")
    end
    if config[:url].to_s.empty?
      abort("Unable to execute unit tests without specifying a url.\nThis can be specified with the environment variable TEST_URL=https://test-appliance\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nurl: https://test-appliance\n")
    end
    if config[:username].to_s.empty?
      abort("Unable to execute unit tests without specifying a username.\nThis can be specified with the environment variable TEST_USERNAME=testrunner\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nusername: testrunner\n")
    end
    if config[:password].to_s.empty?
      abort("Unable to execute unit tests without specifying a password.\nThis can be specified with the environment variable TEST_PASSWORD='SecretPassword123$'\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\npassword: 'SecretPassword123$'\n")
    end
    # debug is not a terminal method right now, set it this way to enable morpheus debugging right away
    if config[:debug]
      Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
    end
  end
  return Thread.current[:config]
end

# todo: set this to true... and hook up --verbose or --trace to see terminal output
QUIET_BY_DEFAULT = false unless defined?(QUIET_BY_DEFAULT)

# Creates a remote for executing unit tests
# This requires the user to set environment variables: TEST_URL, TEST_USERNAME and TEST_PASSWORD or TEST_CONFIG
# By default, test_config.yaml in the current directory can be used.
# The home directory can be specified with TEST_HOME, and the default TEST_CONFIG filename is ~/.morpheus_test
# returns the Morpheus::Terminal instance for executing CLI commands
def establish_test_terminal()
  if Thread.current[:terminal].nil?
    config = get_config()
    if !config[:debug] # || Morpheus::Logging.debug?
      # be quiet by default...
      # doing this this reveals some bad printing in a couple spots...
      if QUIET_BY_DEFAULT
        config[:stdout] = Morpheus::Terminal::Blackhole.new if !config[:stdout]
        config[:stderr] = Morpheus::Terminal::Blackhole.new if !config[:stderr]
      end
    end
    # create the terminal scoped to our test environment
    terminal_opts = {homedir: config[:homedir], stdout: config[:stdout], stderr: config[:stderr], stdin: config[:stdin]}
    Thread.current[:terminal] = Morpheus::Terminal.new(terminal_opts)

    # debug is not a terminal option right now, set it this way instead...
    if config[:debug] # || Morpheus::Logging.debug?
      # Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
      terminal.execute("debug")
    else
      # be quiet by default...
      if QUIET_BY_DEFAULT
        terminal.set_stdout(Morpheus::Terminal::Blackhole.new)
        terminal.set_stderr(Morpheus::Terminal::Blackhole.new)
      end
    end
    # Oh, this actually sets Morpheus::Terminal.instance too.. which is silly
    # Morpheus::Cli.home_directory = config[:homedir]
    # add and use the remote
    # can actually prompt for everything, with a warning...
    # if config[:url].to_s.empty?
    #   puts ""
    #   puts "Warning: You are about to run the CLI unit tests against the specified remote appliance."
    #   puts "Only run these tests against a test or development environment."
    #   puts ""
    #   if config[:remote_name]
    #     terminal.execute("remote add '#{config[:remote_name]}' --use --insecure")
    #   else
    #     terminal.execute("remote add --use --insecure")
    #   end
    # else
      # if config is specified then just add it quietly if it does not exist
      # add remote if it does not exist already
      # ugh this doesn't work, need to fix expression handling apparently..
      #terminal.execute("remote get \"#{config[:remote_name]}\" -q || remote add \"#{config[:remote_name]}\" \"#{config[:url]}\" --insecure --use -N")
    appliance = Morpheus::Cli::Remote.load_remote(config[:remote_name])
    if appliance
      # appliance already exists, update it if needed
      if appliance[:url] != config[:url]
        terminal.execute("remote update \"#{config[:remote_name]}\" --url \"#{escape_arg config[:url]}\" --insecure")
      end
    else
      # create appliance
      terminal.execute("remote add \"#{config[:remote_name]}\" \"#{escape_arg config[:url]}\" --insecure --use -N")
    end
    sleep 1
    # use the remote
    terminal.execute("remote use \"#{config[:remote_name]}\"")

    # could skip this and just let the tests fail that require authentication...
    # login right away to make sure credentials work before attempting to run test suite
    # abort if bad credentials
    #login_status_code, login_error = login()
    login_results = terminal.execute(%(login "#{escape_arg config[:username]}" "#{escape_arg config[:password]}"))
    if login_results[0] == 0
      #print_green_success "Established terminal to #{config[:username]}@#{config[:url]}\nStarting the test run now"
    else
      print_red_alert "Failed to login as #{config[:username]}@#{config[:url]}"
      abort("Test run aborted")
      exit 1
    end
  end
  return Thread.current[:terminal]
end

# use the test remote quietly
def use_remote()
  config = get_config()
  terminal.execute %(remote use #{config[:remote_name]} --quiet)
end

alias :remote_use :use_remote

# @return [true|false]
def is_logged_in()
  return get_access_token() != nil
end

# Fetch the access token for the current remote.
# @return [String,nil] 
def get_access_token()
  config = get_config()
  appliance = Morpheus::Cli::Remote.load_remote(config[:remote_name])
  if appliance.nil?
    #abort("test appliance not found #{config[:remote_name]}")
    return nil
  end
  wallet = ::Morpheus::Cli::Credentials.new(appliance[:name], nil).load_saved_credentials()
  if wallet.nil?
    return nil
  end
  return wallet['access_token']
end

def login_if_needed()
  if !is_logged_in()
    login()
  end
end

def logout_if_needed()
  if is_logged_in()
    logout()
  end
end

# def login()
#   config = get_config()
#   result = terminal.execute(%(login "#{escape_arg config[:username]}" "#{escape_arg config[:password]}" --quiet))
#   exit_code, err = Morpheus::Cli::CliRegistry.parse_command_result(result)
#   if exit_code != 0
#     abort("Failed to login as #{config[:username]}@#{config[:url]}")
#   else
#     # hooray
#   end
# end

def login()
  config = get_config()
  terminal.execute(%(login "#{escape_arg config[:username]}" "#{escape_arg config[:password]}" --quiet))
end

def logout()
  terminal.execute("logout --quiet")
end

# login to execute block and return to previous logged in/out state
def with_authentication(&block)
  was_logged_out = !is_logged_in()
  login_if_needed()
  result = block.call()
  logout_if_needed() if was_logged_out
  return result
end

# logout to execute block and return to previous logged in/out state
def without_authentication(&block)
  was_logged_in = is_logged_in()
  logout_if_needed()
  result = block.call()
  login_if_needed() if was_logged_in
  return result
end

# A mock input for automating input to the test terminal stdin
=begin
class MockInput
  
  def initialize(*messages)
    @messages = [messages].flatten
  end

  def gets
    next_message = @messages.shift
    Morpheus::Logging::DarkPrinter.puts "(DEBUG) Mocking #gets with: #{next_message}" if Morpheus::Logging.debug?
    if next_message
      return next_message.to_s.chomp + "\n"
    else
      # could prompt when run out of messages..
      # right now just hit enter
      #return $stdin.gets()
      return "\n"
    end
  end

  # def readlines
  #   @messages.collect {|s| s + "\n" }
  # end
  
  # act like a File so this works: Readline.input= MockInput.new("exit")
  # def is_a?(type)
  #   type == File || super(type)
  # end

end

def with_input(*messages, &block)
  original_stdin = $stdin #todo: fix terminal to actually use its own stdin, not the global $stdin. for now have to write to a file because need to use Readline.input= File
  begin
    #terminal.set_stdin(MockInput.new(messages))
    $stdin = MockInput.new(messages)
    yield
  ensure
    #terminal.set_stdin(original_stdin)
    $stdin = original_stdin
  end
end
=end

# send input to CLI terminal stdin to handle interactive prompting
def with_input(*messages, &block)
  with_tmpfile_input(*messages, &block)
end

# send input to CLI shell stdin to handle interactive prompting
# def with_shell_input(*messages, &block)
#   with_tmpfile_input(*messages, &block)
# end

# Set stdin to a File (Readline requires a File object for input=)
# this way works for all testing purposes
def with_tmpfile_input(*messages, &block)
  messages = messages.flatten #.compact
  original_stdin = $stdin
  #todo: use temp directory...
  tmpfilename = ".cli_unit_test_shell_input_#{SecureRandom.hex(10)}.morpheus"
  file = nil
  begin
    File.open(tmpfilename, 'w+') {|f| f.write(messages.join("\n") + "\n") }
    file = File.new(tmpfilename, 'r')
    Readline.input = file
    $stdin = file
    yield
  ensure
    Readline.input = original_stdin
    $stdin = original_stdin
    file.close if file && !file.closed?
    File.delete(tmpfilename) if File.exist?(tmpfilename)
  end
end

# escape double quotes for interpolating values between double quotes in your terminal command arguments
def escape_arg(value)
  # escape double quotes
  value.to_s.gsub("\"", "\\\"")
end
