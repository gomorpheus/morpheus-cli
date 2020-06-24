require 'term/ansicolor'
require 'optparse'
require 'json'
require 'rest_client'
require 'net/https'
require 'morpheus/logging'
require 'morpheus/cli/errors'
require 'morpheus/cli/expression_parser'

class Morpheus::Cli::ErrorHandler
  include Term::ANSIColor

  def initialize(io=$stderr)
    @stderr = io
  end

  def handle_error(err, options={})
    exit_code = 1
    options = (options || {}).clone
    if Morpheus::Logging.debug?
      options[:debug] = true
    end
    do_print_stacktrace = true
    
    #@stderr.puts "#{dark}Handling error #{err.class} - #{err}#{reset}"

    case (err)
    when ::OptionParser::InvalidOption, ::OptionParser::AmbiguousOption, 
        ::OptionParser::MissingArgument, ::OptionParser::InvalidArgument, 
        ::OptionParser::NeedlessArgument
      # raise err
      # @stderr.puts "#{red}#{err.message}#{reset}"
      puts_angry_error err.message
      @stderr.puts "Use -h to get help with this command."
      do_print_stacktrace = false
      # exit_code = 127
    # when Morpheus::Cli::CommandArgumentsError
    when Morpheus::Cli::CommandError
      # @stderr.puts "#{red}#{err.message}#{reset}"
      # this should probably print the whole thing as red, but just does the first line for now.
      message_lines = err.message.split(/\r?\n/)
      first_line = message_lines.shift
      puts_angry_error first_line
      @stderr.puts message_lines.join("\n") unless message_lines.empty?
      @stderr.puts "Use -h to get help with this command."
      do_print_stacktrace = false
      if err.exit_code
        exit_code = err.exit_code
      end
    when Morpheus::Cli::ExpressionParser::InvalidExpression
      # @stderr.puts "#{red}#{err.message}#{reset}"
      puts_angry_error err.message
      do_print_stacktrace = false
      exit_code = 99
    when SocketError
      @stderr.puts "#{red}Error Communicating with the remote appliance.#{reset}"
      @stderr.puts "#{red}#{err.message}#{reset}"
    when RestClient::Exceptions::Timeout
      @stderr.puts "#{red}Error Communicating with the remote appliance.#{reset}"
      @stderr.puts "#{red}#{err.message}#{reset}"
    when Errno::ECONNREFUSED
      @stderr.puts "#{red}Error Communicating with the remote appliance.#{reset}"
      @stderr.puts "#{red}#{err.message}#{reset}"
    when OpenSSL::SSL::SSLError
      @stderr.puts "#{red}Error Communicating with the remote appliance.#{reset}"
      @stderr.puts "#{red}#{err.message}#{reset}"
    when RestClient::Exception
      print_rest_exception(err, options)
      # no stacktrace for now...
      return exit_code, err
    when ArgumentError
      @stderr.puts "#{red}Argument Error: #{err.message}#{reset}"
    else
      @stderr.puts "#{red}Unexpected Error#{reset}"
    end

    if do_print_stacktrace
      if options[:debug]
        if err.is_a?(Exception)
          print_stacktrace(err)
        else
          @stderr.puts err.to_s
        end
      else
        @stderr.puts "Use -V or --debug for more verbose debugging information."
      end
    end

    return exit_code, err

  end

  def print_stacktrace(err)
    @stderr.print red, "\n", "#{err.class}: #{err.message}", "\n", reset
    @stderr.print err.backtrace.join("\n"), "\n\n"
  end

  # def handle_rest_exception(err, io=@stderr)
  #   if !err.is_a?(RestClient::Exception)
  #     raise err
  #   end
  #   print_rest_exception(err, io=@stderr)    
  # end


  def print_rest_exception(err, options)
    e = err
    # heh
    if Morpheus::Logging.debug? && options[:debug].nil?
      options[:debug] = true
    end
    if err.response
      if options[:debug]
        begin
          print_rest_exception_request_and_response(e)
        ensure
          @stderr.print reset
        end
        return
      end
      if err.response.code == 400
        begin
          print_rest_errors(JSON.parse(err.response.to_s), options)
        rescue TypeError, JSON::ParserError => ex
        end
      elsif err.response.code == 404
        begin
          print_rest_errors(JSON.parse(err.response.to_s), options)
        rescue TypeError, JSON::ParserError => ex
          # not json, just 404
          @stderr.print red, "Error Communicating with the remote appliance. #{e}", reset, "\n"  
        end
      else
        @stderr.print red, "Error Communicating with the remote appliance. #{e}", reset, "\n"
        if options[:json] || options[:debug]
          begin
            response = JSON.parse(e.response.to_s)
            # @stderr.print red
            @stderr.print JSON.pretty_generate(response)
            @stderr.print reset, "\n"
          rescue TypeError, JSON::ParserError => ex
            @stderr.print red, "Failed to parse JSON response: #{ex}", reset, "\n"
            # @stderr.print red
            @stderr.print response.to_s
            @stderr.print reset, "\n"
          ensure
            @stderr.print reset
          end
        else
          @stderr.puts "Use -V or --debug for more verbose debugging information."
        end
      end
    else
      @stderr.print red, "Error Communicating with the remote appliance. #{e}", reset, "\n"
    end
    # uh, having this print method return exit_code, err to standardize return values of methods that are still calling it, at the end just by chance..
    # return exit_code, err
    return 1, err
  end

  def print_rest_errors(response, options={})
    begin
      if options[:json]
        @stderr.print red
        @stderr.print JSON.pretty_generate(response)
        @stderr.print reset, "\n"
      else
        if !response['success']
          @stderr.print red,bold
          if response['msg']
            @stderr.puts response['msg']
          end
          if response['errors']
            response['errors'].each do |key, value|
              @stderr.print "* #{key}: #{value}\n"
            end
          end
          @stderr.print reset
        else
          # this should not really happen
          @stderr.print cyan,bold, "\nSuccess!"
        end
      end
    ensure
      @stderr.print reset
    end
  end

  def print_rest_request(req)
    @stderr.print "REQUEST"
    @stderr.print "\n"
    @stderr.print "#{req.method.to_s.upcase} #{req.url.inspect}"
    @stderr.print "\n"
  end

  def print_rest_response(res)
    # size = @raw_response ? File.size(@tf.path) : (res.body.nil? ? 0 : res.body.size)
    size = (res.body.nil? ? 0 : res.body.size)
    @stderr.print "RESPONSE"
    @stderr.print "\n"
    display_size = Filesize.from("#{size} B").pretty rescue size
    @stderr.print "HTTP #{res.net_http_res.code} #{res.net_http_res.message} | #{(res['Content-type'] || '').gsub(/;.*$/, '')} #{display_size}"
    @stderr.print "\n"
    begin
      @stderr.print JSON.pretty_generate(JSON.parse(res.body))
    rescue
      @stderr.print res.body.to_s
    end
    @stderr.print "\n"
  end

  def print_rest_exception_request_and_response(e)
    @stderr.puts "#{red}Error Communicating with the remote appliance. (HTTP #{e.response.code})#{reset}"
    response = e.response
    request = response.instance_variable_get("@request")
    @stderr.print red
    print_rest_request(request)
    @stderr.print "\n"
    print_rest_response(response)
    @stderr.print reset
  end


protected
  
  def puts_angry_error(*msgs)
    # @stderr.print "#{Term::ANSIColor.red}morpheus: #{Term::ANSIColor.reset}#{msg}\n"
    @stderr.print(Morpheus::Terminal.angry_prompt)
    @stderr.print(Term::ANSIColor.red)
    @stderr.puts(*msgs)
    @stderr.print(reset)
  end

  # def puts(*args)
  #   @stderr.puts(*args) 
  # end

  # def print(*args)
  #   @stderr.print(*args)
  # end

end
