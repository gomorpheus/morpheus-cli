module Morpheus::Cli

  # A standard error to raise in your CliCommand classes.
  class CommandError < StandardError
    
    attr_reader :args, :exit_code
      
    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      @args = args
      @optparse = optparse
      @exit_code = exit_code # || 1
      super(msg)
    end
  end

  # An error indicating the command was not recoginzed
  class CommandNotFoundError < CommandError
    
    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      super(msg, args, optparse, exit_code || 127)
    end

  end

  # An error for wrong number of arguments
  # could use ::OptionParser::MissingArgument, ::OptionParser::NeedlessArgument
  # maybe return an error code niftier than 1?
  class CommandArgumentsError < CommandError

    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      super(msg, args, optparse, exit_code || 1)
    end

  end

  # An error indicating authorization is required (unable to aquire access token)
  class AuthorizationRequiredError < CommandError

    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      super(msg, args, optparse, exit_code || 1)
    end

  end

end
