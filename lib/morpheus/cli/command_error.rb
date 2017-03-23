# A standard error to raise in your CliCommand classes.
class Morpheus::Cli::CommandError < StandardError
  
  # attr_reader :args, :options
    
  # def initialize(msg, args=[], options={})
  #   @args = args
  #   @options = options
  #   super(msg)
  # end

end
