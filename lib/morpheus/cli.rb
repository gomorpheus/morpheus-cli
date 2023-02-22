require 'morpheus/cli/version'
require 'morpheus/cli/errors'
require 'morpheus/rest_client'
require 'morpheus/formatters'
require 'morpheus/logging'
require 'morpheus/util'
require 'morpheus/routes'
require 'term/ansicolor'

Dir[File.dirname(__FILE__)  + "/ext/*.rb"].each {|file| require file }

module Morpheus
  module Cli
    
    # The default is $MORPHEUS_CLI_HOME or $HOME/.morpheus
    unless defined?(@@home_directory)
      @@home_directory = ENV['MORPHEUS_CLI_HOME'] || File.join(Dir.home, ".morpheus")
    end
    
    # get the home directory, where morpheus-cli stores things
    def self.home_directory
      @@home_directory
    end

    # set the home directory
    def self.home_directory=(fn)
      @@home_directory = fn
    end

    # check if this is a Windows environment.
    def self.windows?
      if defined?(@@is_windows)
        return @@is_windows
      end
      @@is_windows = false
      begin
        require 'rbconfig'
        @@is_windows = (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
      rescue
        # $stderr.puts "unable to determine if this is a Windows machine."
      end
      return @@is_windows
    end

    # load! does the initial loading of all the CLI utilities and commands
    def self.load!()
      
      # api interfaces
      require 'morpheus/api'
      Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each { |file| require file }

      # utilites
      # Dir[File.dirname(__FILE__)  + "/cli/*.rb"].each { |file| require file }
      require 'morpheus/cli/cli_registry.rb'
      require 'morpheus/cli/expression_parser.rb'
      require 'morpheus/cli/dot_file.rb'
      require 'morpheus/cli/errors'
      require 'morpheus/cli/cli_command.rb'
      require 'morpheus/cli/option_types.rb'
      require 'morpheus/cli/credentials.rb'

      # mixins
      Dir[File.dirname(__FILE__)  + "/cli/mixins/**/*.rb"].each {|file| require file }
      
      # commands
      Dir[File.dirname(__FILE__)  + "/cli/commands/**/*.rb"].each {|file| require file }

    end

    # reload! can be used for live reloading changes while developing
    def self.reload!()
      # api interfaces
      Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each { |file| load file }
      # mixins
      Dir[File.dirname(__FILE__)  + "/cli/mixins/**/*.rb"].each {|file| load file }
      # commands
      Dir[File.dirname(__FILE__)  + "/cli/commands/**/*.rb"].each {|file| load file }
    end

    # hack needed for unit tests right now
    @@testing = false unless defined?(@@testing)

    # hack needed for unit tests right now
    def self.enable_test_mode
      @@testing = true
    end

    # hack needed for unit tests right now
    def self.testing?
      defined?(@@testing) && @@testing == true
    end

    # require all CLI modules now (on require)
    load!
    
  end

end
