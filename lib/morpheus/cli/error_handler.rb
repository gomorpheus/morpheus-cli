require 'term/ansicolor'
require 'optparse'
#require 'rest_client'
require 'morpheus/logging'
class Morpheus::Cli::ErrorHandler
  include Morpheus::Cli::PrintHelper

  def handle_error(err, options={})
    # heh
    if Morpheus::Logging.debug? && options[:debug].nil?
      options[:debug] = true
    end
    case (err)
    when OptionParser::InvalidOption, OptionParser::AmbiguousOption, OptionParser::MissingArgument, OptionParser::InvalidArgument
      # raise err
      print_red_alert "#{err.message}"
      puts "Try -h for help with this command."
    when Errno::ECONNREFUSED
      print_red_alert "#{err.message}"
      # more special errors?
    when OpenSSL::SSL::SSLError
      print_red_alert "Error Communicating with the Appliance. #{err.message}"
    when RestClient::Exception
      print_rest_exception(err, options)
    else
      print_red_alert "Unexpected Error."
      if !options[:debug]
        print "Use --debug for more information.\n"
      end
    end

    if options[:debug]
      print Term::ANSIColor.red, "\n", "#{err.class}: #{err.message}", "\n", Term::ANSIColor.reset
      print err.backtrace.join("\n"), "\n\n"
    else
      #print "Use --debug for more information.\n"
    end
  end

end
