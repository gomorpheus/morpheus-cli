require 'morpheus/cli/version'
require 'morpheus/cli/errors'
require 'morpheus/rest_client'
require 'morpheus/formatters'
require 'morpheus/logging'
require 'morpheus/util'
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
      rescue => ex
        # $stderr.puts "unable to determine if this is a Windows machine."
      end
      return @@is_windows
    end

    # load all the well known commands and utilties they need
    def self.load!()
      # load interfaces
      require 'morpheus/api/api_client.rb'
      require 'morpheus/api/rest_interface.rb'
      require 'morpheus/api/read_interface.rb'
      Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each {|file| load file }

      # load mixins
      Dir[File.dirname(__FILE__)  + "/cli/mixins/**/*.rb"].each {|file| load file }

      # load utilites
      require 'morpheus/cli/cli_registry.rb'
      require 'morpheus/cli/expression_parser.rb'
      require 'morpheus/cli/dot_file.rb'
      require 'morpheus/cli/errors'

      load 'morpheus/cli/cli_command.rb'
      load 'morpheus/cli/option_types.rb'
      load 'morpheus/cli/credentials.rb'
      
      # load all commands
      Dir[File.dirname(__FILE__)  + "/cli/commands/**/*.rb"].each {|file| load file }

    end

    load!
    
  end

end
