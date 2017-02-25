require 'term/ansicolor'
require 'optparse'
#require 'rest_client'
require 'morpheus/logging'
class Morpheus::Cli::ErrorHandler
    
  include Morpheus::Cli::PrintHelper

  def handle_error(err)
    case (err) 
    when OptionParser::InvalidOption, OptionParser::AmbiguousOption, OptionParser::MissingArgument, OptionParser::InvalidArgument
      # raise e
      print_red_alert "#{err.message}"
      puts "Try -h for help with this command."
    when Errno::ECONNREFUSED
      print_red_alert "#{err.message}"
    # more special errors?
    when RestClient::Exception
      #print_rest_exception(err, options)
      print_rest_exception(err)
    else
      print_red_alert "Unexpected Error"
    end

    if Morpheus::Logging.print_stacktrace?
      print Term::ANSIColor.red, "\n", "#{err.class}: #{err.message}", "\n", Term::ANSIColor.reset
      print err.backtrace.join("\n"), "\n\n"
    end
  end

end
