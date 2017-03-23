require 'term/ansicolor'
require 'optparse'
#require 'rest_client'
require 'morpheus/logging'
require 'morpheus/cli/command_error'
class Morpheus::Cli::ErrorHandler
  include Morpheus::Cli::PrintHelper

  def handle_error(err, options={})
    # heh
    if Morpheus::Logging.debug? && options[:debug].nil?
      options[:debug] = true
    end
    do_print_stacktrace = true
    case (err)
    when ::OptionParser::InvalidOption, ::OptionParser::AmbiguousOption, 
        ::OptionParser::MissingArgument, ::OptionParser::InvalidArgument, 
        ::OptionParser::NeedlessArgument
      # raise err
      $stderr.puts "#{red}#{err.message}#{reset}"
      $stderr.puts "Try -h for help with this command."
      do_print_stacktrace = false
    when Morpheus::Cli::CommandError
      $stderr.puts "#{red}#{err.message}#{reset}"
      do_print_stacktrace = false
      # $stderr.puts "Try -h for help with this command."
    when Errno::ECONNREFUSED
      $stderr.puts "#{red}Error Communicating with the Appliance.#{reset}"
      $stderr.puts "#{red}#{err.message}#{reset}"
      # $stderr.puts "Try -h for help with this command."
    when OpenSSL::SSL::SSLError
      $stderr.puts "#{red}Error Communicating with the Appliance.#{reset}"
      $stderr.puts "#{red}#{err.message}#{reset}"
    when RestClient::Exception
      # $stderr.puts "#{red}Error Communicating with the Appliance.#{reset}"
      # $stderr.puts "#{red}#{err.message}#{reset}"
      print_rest_exception(err, options)
    else
      $stderr.puts "#{red}Unexpected Error#{reset}"
    end

    if do_print_stacktrace
      if options[:debug]
        print_stacktrace(err)
      else
        $stderr.puts "Use --debug for more information."
      end
    end
  end

  def print_stacktrace(err, io=$stderr)
    io.print red, "\n", "#{err.class}: #{err.message}", "\n", reset
    io.print err.backtrace.join("\n"), "\n\n"
  end

end
