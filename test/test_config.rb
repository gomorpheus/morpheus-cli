# use a different default home directory when running tests
ENV['MORPHEUS_CLI_HOME'] = ENV['TEST_CLI_HOME'] || File.join(Dir.home, ".morpheus_test") unless ENV['MORPHEUS_CLI_HOME']
require 'morpheus'

module MorpheusTest
  
  # TestConfig handles parsing of the Morpheus test config settings
  # This parses environment variables or a config file, the latter takes priority
  # The default config file named +test_config.yaml+
  class TestConfig
    include Morpheus::Cli::PrintHelper # for parse_json_or_yaml() todo: remove this include and use a class method

    # The default filename for the test config
    DEFAULT_FILENAME = 'test_config.yaml'

    # The environment variables that are parsed and the corresponding config property name
    ENVIRONMENT_VARIABLES = {
      # "TEST_CLI_HOME" => :homedir, 
      "TEST_REMOTE_NAME" => :remote_name, 
      "TEST_REMOTE_URL" => :url, 
      "TEST_URL" => :url,
      "TEST_USERNAME" => :username,
      "TEST_PASSWORD" => :password,
      "TEST_DEBUG" => :debug, 
      "DEBUG" => :debug,
    }.freeze

    # The default name of the remote to create and do our unit testing in
    DEFAULT_REMOTE_NAME = 'unit_test'

    # use a different default home directory when running tests
    # load settings from environment variables and config file
    # unless ENV['MORPHEUS_CLI_HOME']
    #   ENV['MORPHEUS_CLI_HOME'] = File.join(Dir.home, ".morpheus_test")
    # end
    # The default name of the remote to create and use for unit testing
    DEFAULT_HOMEDIR = Morpheus::Cli.home_directory

    # raised if the config cannot be parsed or is missing required settings
    class BadConfigError < StandardError
    end

    attr_accessor :homedir, :remote_name, :url, :username
    attr_writer :password
    attr_reader :debug
  
    def initialize
      # set defaults
      @remote_name = DEFAULT_REMOTE_NAME # 'unit_test'
      @homedir = DEFAULT_HOMEDIR # Morpheus::Cli.home_directory
      
      # load settings from environment variable and set instance variables
      #ENVIRONMENT_VARIABLES.each { |name, value| instance_variable_set("@#{name}", ENV[name]) if ENV[name] }
      ENVIRONMENT_VARIABLES.each { |name, value| send("#{value}=", ENV[name]) if ENV[name] }

      # load settings from config file
      config_filename = nil
      if ENV['TEST_CONFIG']
        config_filename = ENV['TEST_CONFIG']
      elsif File.exist?(DEFAULT_FILENAME)
        config_filename = DEFAULT_FILENAME
      elsif File.exist?(File.join(homedir, DEFAULT_FILENAME))
        config_filename = File.join(@homedir, DEFAULT_FILENAME)
      end
      if config_filename
        full_filename = File.expand_path(config_filename)
        file_content = nil
        if File.exist?(full_filename)
          file_content = File.read(full_filename)
        else
          raise "Test config file not found: #{full_filename}"
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          bad_config "Failed to parse test config file '#{config_filename}' as YAML or JSON. Error: #{parse_result[:error]}"
        end
        @homedir = config_map['homedir'] if config_map['homedir']
        @remote_name = config_map['remote_name'] if config_map['remote_name']
        @url = (config_map['url'] || config_map['remote_url']) if (config_map['url'] || config_map['remote_url'])
        @username = config_map['username'] if config_map['username']
        @password = config_map['password'] if config_map['password']
        @debug = config_map['debug'].to_s.strip.downcase == "true" if config_map.key?('debug')
      end
      
      # print_h1 "Test Config"
      # print cyan
      # puts "homedir: #{homedir}"
      # puts "remote_name: #{remote_name}"
      # puts "url: #{url}"
      # puts "username: #{username}"
      # puts "password: #{password}"
      # print reset

      # validate now
      # For now force user to create a test_config.yaml or use environment variables
      if remote_name.to_s.empty?
        bad_config "Unable to execute unit tests without specifying a remote name.\nYou must specify the environment variable TEST_REMOTE_NAME=unit_test\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nremote_name: unit_test\n"
      end
      if url.to_s.empty?
        bad_config "Unable to execute unit tests without specifying a url.\nThis can be specified with the environment variable TEST_URL=https://test-appliance\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nurl: https://test-appliance\n"
      end
      if username.to_s.empty?
        bad_config "Unable to execute unit tests without specifying a username.\nThis can be specified with the environment variable TEST_USERNAME=testrunner\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\nusername: testrunner\n"
      end
      if password.to_s.empty?
        bad_config "Unable to execute unit tests without specifying a password.\nThis can be specified with the environment variable TEST_PASSWORD='SecretPassword123$'\nor in a config file named #{config_filename || 'test_config.yaml'} like this:\n\npassword: 'SecretPassword123$'\n"
      end
      # debug is not a terminal method right now, set it this way to enable morpheus debugging right away
      if debug
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
      end
      
      # todo: test authentication now...
      # config looks good
    end

    def password
      @password ? ('*' * 12) : nil
    end

    def password_decrypted
      @password
    end

    def debug=(v)
      @debug = v.to_s.strip.downcase == "true"
    end

    def bad_config(msg)
      #todo: make this work with raise but also don't run every test so just abort for now
      #raise BadConfigError.new(msg)
      print_red_alert msg
      abort("Aborting tests...")
    end
  end
end