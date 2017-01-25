require 'term/ansicolor'
require 'json'

module Morpheus::Cli::PrintHelper

  def self.included(klass)
    klass.send :include, Term::ANSIColor
  end

  def print_red_alert(msg)
    print red, bold, "\n#{msg}\n\n", reset
  end

  def print_yellow_warning(msg)
    print yellow, bold, "\n#{msg}\n\n", reset
  end

  def print_green_success(msg)
    print green, bold, "\n#{msg}\n\n", reset
  end

  def print_errors(response, options={})
    begin
      if options[:json]
        print red, "\n"
        print JSON.pretty_generate(response)
        print reset, "\n\n"
      else
        if !response['success']
          print red,bold, "\n"
          if response['msg']
            puts response['msg']
          end
          if response['errors']
            response['errors'].each do |key, value|
              print "* #{key}: #{value}\n"
            end
          end
          print reset, "\n"
        else
          # this should not really happen
          print cyan,bold, "\nSuccess!"
        end
      end
    ensure
      print reset
    end
  end

  def print_rest_exception(e, options={})
    if e.response
      if e.response.code == 400
        response = JSON.parse(e.response.to_s)
        print_errors(response, options)
      else
        print_red_alert "Error Communicating with the Appliance. (#{e.response.code}) #{e}"
        if options[:json]
          begin
            response = JSON.parse(e.response.to_s)
            print red, "\n"
            print JSON.pretty_generate(response)
            print reset, "\n\n"
          rescue TypeError, JSON::ParserError => ex
            #print_red_alert "Failed to parse JSON response: #{ex}"
          ensure
            print reset
          end
        end
      end
    else
      print_red_alert "Error Communicating with the Appliance. #{e}"
    end
  end

  def required_blue_prompt
    "#{cyan}|#{reset}"
  end
end
