# This handles setting up the environment executing the CLI test cases.
# so that in your TestCase classes you can do the following:
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


# require dependencies
# using test-unit gem for unit tests
# require 'test/unit'
# TestCase is the our base Test::Unit::TestCase
require 'test_case'

# use a different default home directory when running tests
# load settings from environment variables and config file
unless ENV['MORPHEUS_CLI_HOME']
  ENV['MORPHEUS_CLI_HOME'] = File.join(Dir.home, ".morpheus_test")
end

# load morpheus CLI library
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'morpheus'
#todo: Probably add tests for all modules, separating Morpheus::Cli and Morpheus::Api
# require 'morpheus/api'
# require 'morpheus/cli'
# PrintHelper for parse_json_or_yaml()
include Morpheus::Cli::PrintHelper


#################################
## Setup Hooks
#################################

#Hook that runs once at the end of all tests
Test::Unit.at_exit {
  #puts "Test Suite Complete"
  # always logout when all done
  logout_if_needed()
}


#################################
## CLI Test Assertions
#################################

# Execute the command and assert the result
# By default, the result should be a success with exit code: 0 and error: nil
# @param [Hash] options. See +assert_command_result+
def assert_execute(cmd, options = {})
  options = options.is_a?(String) ? {failure:options} : (options || {})
  result = terminal.execute(cmd)
  assert_command_result(result, options)
end

# +assert_success()+ is an alias for +assert_execute()+
alias :assert_success :assert_execute

# execute the command and assert that the result is in an error (exit non-0)
# use options {exit:1, error: "something bad happened"} to assert a specific error exit code and/or message
def assert_error(cmd, options = {})
  options = options.is_a?(String) ? {failure:options} : (options || {})
  assert_execute(cmd, options.merge(success:false))
end

# assert that a command is has the expected exit status and message
# The default behavior is to assert the result is successful, exit: 0, error: nil
# use {success:false} to assert non-zero
# or use {exit:1, error: "something bad happened"} to assert a specific error exit and/or message
def assert_command_result(result, options = {})
  # determine what to assert
  success = options.key?(:success) ? options[:success] : true
  expected_code = options[:exit] ? options[:exit] : (success ? 0 : nil)
  if expected_code && expected_code != 0
    success = false
  end
  expected_message = options[:error]
  failure_message = options[:failure] || options[:failure_message]
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

#################################
## CLI Helpers methods
#################################

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
    config[:stdout] = ENV['TEST_STDOUT']
    config[:stderr] = ENV['TEST_STDERR']
    config[:stdin] = ENV['TEST_STDIN']
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
        abort("Failed to parse test config file '#{config_filename}' as YAML or JSON. Error: #{parse_result[:err]}")
      end
      config[:homedir] = config_map['homedir'] if config_map['homedir']
      config[:remote_name] = config_map['remote_name'] if config_map['remote_name']
      config[:url] = (config_map['url'] || config_map['remote_url']) if (config_map['url'] || config_map['remote_url'])
      config[:username] = config_map['username'] if config_map['username']
      config[:password] = config_map['password'] if config_map['password']
      config[:stdout] = config_map['stdout'] if config_map['stdout']
      config[:stderr] = config_map['stderr'] if config_map['stderr']
      config[:stdin] = config_map['stdin'] if config_map['stdin']
      config[:debug] = config_map['debug'].to_s.strip.downcase == "true" if config_map.key?('debug')
      # config[:quiet] = config_map['temporary'].to_s.strip.downcase == "true" if config_map.key?'temporary')
      # config[:temporary] = config_map['temporary'].to_s.strip.downcase == "true" if config_map.key?'temporary')
    end
    # COULD maybe prompt for all of these for inital setup
    # FOR NOW force user to create a test_config.yaml
    if config[:remote_name].to_s.empty?
      abort("Unable to execute unit tests without specifiying a remote name.\You must specify the environment variable TEST_REMOTE_NAME=unit_test\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nremote_name: unit_test\n")
    end
    if config[:url].to_s.empty?
      abort("Unable to execute unit tests without specifiying a url.\nThis can be specified with the environment variable TEST_URL=https://test-appliance\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nurl: https://test-appliance\n")
    end
    if config[:username].to_s.empty?
      abort("Unable to execute unit tests without specifiying a username.\nThis can be specified with the environment variable TEST_USERNAME=testrunner\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nusername: testrunner\n")
    end
    if config[:password].to_s.empty?
      abort("Unable to execute unit tests without specifiying a password.\nThis can be specified with the environment variable TEST_PASSWORD='SecretPassword123$'\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\npassword: 'SecretPassword123$'\n")
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
    terminal_options = {homedir: config[:homedir], stdout: config[:stdout], stderr: config[:stderr], stdin: config[:stdin]}
    Thread.current[:terminal] = Morpheus::Terminal.new(terminal_options)
    # debug is not a terminal option right now, set it this way instead...
    if config[:debug] # || Morpheus::Logging.debug?
      # Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
      Thread.current[:terminal].execute("debug")
    else
      # be quiet by default...
      if QUIET_BY_DEFAULT
        Thread.current[:terminal].set_stdout(Morpheus::Terminal::Blackhole.new)
        Thread.current[:terminal].set_stderr(Morpheus::Terminal::Blackhole.new)
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
      #Thread.current[:terminal].execute("remote get \"#{config[:remote_name]}\" -q || remote add \"#{config[:remote_name]}\" \"#{config[:url]}\" --insecure --use -N")
      appliance = Morpheus::Cli::Remote.load_remote(config[:remote_name])
      if appliance
        # appliance already exists
      else
        # create appliance
        Thread.current[:terminal].execute("remote add \"#{config[:remote_name]}\" \"#{config[:url]}\" --insecure --use -N")
      end

      #wallet = ::Morpheus::Cli::Credentials.new(appliance[:name], nil).load_saved_credentials()
    # end
    # use the remote
    Thread.current[:terminal].execute("remote use \"#{config[:remote_name]}\"")
    # login right away maybe?
    # login_if_needed()
    
    # print_green_success "Established terminal to #{config[:username]}@#{config[:url]}\nThe CLI unit tests will begin soon..."
    # sleep 3
  end
  return Thread.current[:terminal]
end

# use the test remote quietly
def use_remote()
  config = get_config()
  terminal.execute %(remote use #{config[:remote_name]} --quiet)
end

alias :remote_use :use_remote

# todo: use Morpheus::Cli::Remote to see if login is needed
# right now using a hacky flag here determine if we are logged in or not
def is_logged_in()
  #wallet = ::Morpheus::Cli::Credentials.new(appliance[:name], nil).load_saved_credentials()
  return get_access_token() != nil
end

def get_access_token()
  config = get_config()
  appliance = Morpheus::Cli::Remote.load_remote(config[:remote_name])
  if appliance.nil?
    abort("test appliance not found #{config[:remote_name]}")
    return nil
  end
  wallet = ::Morpheus::Cli::Credentials.new(appliance[:name], nil).load_saved_credentials()
  if wallet.nil?
    return nil
  end
  return wallet['access_token']
end

def login_if_needed()
  # todo: can actually use Morpheus::Cli::Remote to see if login is needed
  # if terminal.logged_in?
  # else
  # end
  if !is_logged_in()
    login()
  end
  true
end

def logout_if_needed()
  if is_logged_in()
    logout()
  end
  true
end

def login()
  config = get_config()
  terminal.execute("login '#{config[:username]}' '#{config[:password]}'")
end

def logout()
  terminal.execute("logout")
end

def assert_login()
  assert_execute(login())
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