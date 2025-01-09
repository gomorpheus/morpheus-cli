require 'test/unit'
# use a different default home directory when running tests
ENV['MORPHEUS_CLI_HOME'] = ENV['TEST_CLI_HOME'] || File.join(Dir.home, ".morpheus_test")
require 'morpheus'
require 'test_config'
#require 'securerandom'

# hack needed for unit tests right now
Morpheus::Cli.enable_test_mode()

module MorpheusTest

  # TestCase is the base class for all unit tests to provide standard behavior
  # for testing CLI commands and API interfaces.
  #
  # +assert_execute+ is available to execute a CLI command or expression and assert the result is a success (exit:0) by default.
  #
  # +terminal+ is available to execute any commands eg. +terminal.execute("source foo")+
  #
  # +client+ is available for executing API requests
  #
  class TestCase < Test::Unit::TestCase
    include Morpheus::Cli::PrintHelper # printhelper for print_red_alert and what not.. should probably not be included in MorpheusTest

    # execute test cases in the order they are defined.
    self.test_order = :defined

    # indicates the test requires the user to have a current remote
    # override this to return false if your tests do not require `remote use` as part of its setup
    def requires_remote
      true
    end

    # indicates the test requires the user to be logged in and authenticated
    # override this to return false if your tests do not require `login` as part of its setup
    def requires_authentication
      true
    end

    # hook at the beginning of each test
    def setup()
      #puts "TestCase #{self} setup()"
      # @config is provided for accessing test environment settings in our tests
      @config = get_config()
      # use the remote and login if needed
      use_remote() if requires_remote
      login_if_needed() if requires_authentication
    end

    # hook at the end of each test
    def teardown()
      #puts "TestCase #{self} teardown()"
      #logout_if_needed() if requires_authentication
    end

    # def initialize(*args)
    #   obj = super(*args)
    #   @client = establish_test_terminal()
    # end

    protected

     # @return [Morpheus::APIClient] client for executing api requests in our tests and examining the results
    def client
      # todo: return terminal.get_api_client()
      #@api_client ||= Morpheus::APIClient.new(url: @config.url, username: @config.username, password: @config.password_decrypted, verify_ssl: false, client_id: 'morph-api')
      #@api_client.login() unless @api_client.logged_in?
      # this only works while logged in, fine for now...
      @client ||= Morpheus::APIClient.new(url: @config.url, username: @config.username, password: @config.password, access_token: get_access_token(), verify_ssl: false, client_id: 'morph-cli')
    end

   

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
      Morpheus::Logging::DarkPrinter.puts(cmd)
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
      Thread.current[:config] ||= TestConfig.new
    end

    # todo: make this work IOError unitialized stream right now
    QUIET = ENV['QUIET'] ? true : false unless defined?(QUIET)

    # Creates a remote for executing unit tests
    # This requires the user to set environment variables: TEST_URL, TEST_USERNAME and TEST_PASSWORD or TEST_CONFIG
    # By default, test_config.yaml in the current directory can be used.
    # The home directory can be specified with TEST_HOME, and the default TEST_CONFIG filename is ~/.morpheus_test
    # returns the Morpheus::Terminal instance for executing CLI commands
    def establish_test_terminal()
      if Thread.current[:terminal].nil?
        config = get_config()

        # create the terminal scoped to our test environment
        terminal_opts = {homedir: config.homedir}
        Thread.current[:terminal] = Morpheus::Terminal.new(terminal_opts)

        # debug is not a terminal option right now, set it this way instead...
        if config.debug # || Morpheus::Logging.debug?
          # Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
          terminal.execute("debug")
        else
          if QUIET
            #blackhole = Morpheus::Terminal::Blackhole.new('blackhole')
            blackhole = File.open(Morpheus::Cli.windows? ? 'NUL:' : '/dev/null', 'w')
            terminal.set_stdout(blackhole)
            terminal.set_stderr(blackhole)
          end
        end
        
        #terminal.execute("remote get \"#{config.remote_name}\" -q || remote add \"#{config.remote_name}\" \"#{config.url}\" --insecure --use -N")
        appliance = Morpheus::Cli::Remote.load_remote(config.remote_name)
        if appliance
          # appliance already exists, update it if needed
          if appliance[:url] != config.url
            terminal.execute("remote update \"#{config.remote_name}\" --url \"#{escape_arg config.url}\" --insecure")
          end
        else
          # create appliance
          terminal.execute("remote add \"#{config.remote_name}\" \"#{escape_arg config.url}\" --insecure --use -N")
        end
        sleep 1
        # use the remote
        terminal.execute("remote use \"#{config.remote_name}\"")

        # could skip this and just let the tests fail that require authentication...
        # login right away to make sure credentials work before attempting to run test suite
        # abort if bad credentials
        #login_status_code, login_error = login()
        login_results = terminal.execute(%(login "#{escape_arg config.username}" "#{escape_arg config.password_decrypted}"))
        if login_results[0] == 0
          #print_green_success "Established terminal to #{config.username}@#{config.url}\nStarting the test run now"
        else
          print_red_alert "Failed to login as #{config.username}@#{config.url}"
          abort("Test run aborted")
          exit 1
        end
      end
      return Thread.current[:terminal]
    end

    # use the test remote quietly
    def use_remote()
      config = get_config()
      terminal.execute %(remote use #{config.remote_name} --quiet)
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
      appliance = Morpheus::Cli::Remote.load_remote(config.remote_name)
      if appliance.nil?
        #abort("test appliance not found #{config.remote_name}")
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
    #   result = terminal.execute(%(login "#{escape_arg config.username}" "#{escape_arg config.password_decrypted}" --quiet))
    #   exit_code, err = Morpheus::Cli::CliRegistry.parse_command_result(result)
    #   if exit_code != 0
    #     abort("Failed to login as #{config.username}@#{config.url}")
    #   else
    #     # hooray
    #   end
    # end

    def login()
      config = get_config()
      terminal.execute(%(login "#{escape_arg config.username}" "#{escape_arg config.password_decrypted}" --quiet))
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

  end
end
