require 'term/ansicolor'
require 'optparse'
require 'rest_client'
require 'net/https'
require 'morpheus/logging'
require 'morpheus/cli/command_error'
class Morpheus::Cli::ErrorHandler
  include Morpheus::Cli::PrintHelper

  def handle_error(err, options={})
    exit_code = 1
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
      # $stderr.puts "#{red}#{err.message}#{reset}"
      puts_angry_error err.message
      $stderr.puts "Try -h for help with this command."
      do_print_stacktrace = false
      # exit_code = 127
    when Morpheus::Cli::CommandError
      # $stderr.puts "#{red}#{err.message}#{reset}"
      puts_angry_error err.message
      do_print_stacktrace = false
      # $stderr.puts "Try -h for help with this command."
    when SocketError
      $stderr.puts "#{red}Error Communicating with the Appliance.#{reset}"
      $stderr.puts "#{red}#{err.message}#{reset}"
    when RestClient::Exceptions::Timeout
      $stderr.puts "#{red}Error Communicating with the Appliance.#{reset}"
      $stderr.puts "#{red}#{err.message}#{reset}"
    when Errno::ECONNREFUSED
      $stderr.puts "#{red}Error Communicating with the Appliance.#{reset}"
      $stderr.puts "#{red}#{err.message}#{reset}"
      # $stderr.puts "Try -h for help with this command."
    when OpenSSL::SSL::SSLError
      $stderr.puts "#{red}Error Communicating with the Appliance.#{reset}"
      $stderr.puts "#{red}#{err.message}#{reset}"
    when RestClient::Exception
      print_rest_exception(err, options)
    else
      $stderr.puts "#{red}Unexpected Error#{reset}"
    end

    if do_print_stacktrace
      if options[:debug]
        if err.is_a?(Exception)
          print_stacktrace(err)
        else
          $stderr.puts err.to_s
        end
      else
        $stderr.puts "Use --debug for more information."
      end
    end

    return exit_code

  end

  def print_error
    angry_prompt
  end

  def print_stacktrace(err, io=$stderr)
    io.print red, "\n", "#{err.class}: #{err.message}", "\n", reset
    io.print err.backtrace.join("\n"), "\n\n"
  end

protected
  
  def puts_angry_error(msg)
    $stderr.print "#{Term::ANSIColor.red}morpheus: #{Term::ANSIColor.reset}#{msg}\n"
  end

  
  # def puts(*args)
  #   $stderr.puts(*args) 
  # end

  # def print(*args)
  #   $stderr.print(*args) 
  # end

end
