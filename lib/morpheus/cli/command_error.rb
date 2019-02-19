# A standard error to raise in your CliCommand classes.
class Morpheus::Cli::CommandError < StandardError
  
  attr_reader :args, :exit_code
    
  # def initialize(msg, args=[], options={})
  #   @args = args
  #   @options = options
  #   super(msg)
  # end

  def initialize(msg, args=[], exit_code=nil)
    @args = args
    @exit_code = exit_code
    super(msg)
  end

end
