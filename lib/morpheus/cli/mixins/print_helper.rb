require 'uri'
require 'term/ansicolor'
require 'json'

module Morpheus::Cli::PrintHelper

  def self.included(klass)
    klass.send :include, Term::ANSIColor
  end

  def print_red_alert(msg)
    print red,  "\n#{msg}\n", reset
  end

  def print_yellow_warning(msg)
    print yellow, "\n#{msg}\n", reset
  end

  def print_green_success(msg)
    print green, "\n#{msg}\n", reset
  end

  def print_errors(response, options={})
    begin
      if options[:json]
        print red
        print JSON.pretty_generate(response)
        print reset, "\n"
      else
        if !response['success']
          print red,bold
          if response['msg']
            puts response['msg']
          end
          if response['errors']
            response['errors'].each do |key, value|
              print "* #{key}: #{value}\n"
            end
          end
          print reset
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
      if options[:debug]
        begin
          print_rest_exception_request_and_response(e)
        ensure
          print reset
        end
        return
      end
      if e.response.code == 400
        response = JSON.parse(e.response.to_s)
        print_errors(response, options)
      else
        print_red_alert "Error Communicating with the Appliance. #{e}"
        if options[:json] || options[:debug]
          begin
            response = JSON.parse(e.response.to_s)
            print red
            print JSON.pretty_generate(response)
            print reset, "\n"
          rescue TypeError, JSON::ParserError => ex
            print_red_alert "Failed to parse JSON response: #{ex}"
            print red
            print response.to_s
            print reset, "\n"
          ensure
            print reset
          end
        end
      end
    else
      print_red_alert "Error Communicating with the Appliance. #{e}"
    end
  end

  def print_rest_request(req)
    # JD: IOError when accessing payload... we should probably just be printing at the time the request is made..
    #out = []
    #out << "#{req.method} #{req.url.inspect}"
    #out << req.payload.short_inspect if req.payload
    # payload = req.instance_variable_get("@payload")
    # out << payload if payload
    #out << req.processed_headers.to_a.sort.map { |(k, v)| [k.inspect, v.inspect].join("=>") }.join(", ")
    #print out.join(', ') + "\n"
    print "Request:"
    print "\n"
    print "#{req.method.to_s.upcase} #{req.url.inspect}"
    print "\n"
  end

  def print_rest_response(res)
    # size = @raw_response ? File.size(@tf.path) : (res.body.nil? ? 0 : res.body.size)
    size = (res.body.nil? ? 0 : res.body.size)
    print "Response:"
    print "\n"
    display_size = Filesize.from("#{size} B").pretty rescue size
    print "HTTP #{res.net_http_res.code} - #{res.net_http_res.message} | #{(res['Content-type'] || '').gsub(/;.*$/, '')} #{display_size}"
    print "\n"
    begin
      print JSON.pretty_generate(JSON.parse(res.body))
    rescue
      print res.body.to_s
    end
    print "\n"
  end

  def print_rest_exception_request_and_response(e)
    print_red_alert "Error Communicating with the Appliance. (#{e.response.code}) #{e}"
    response = e.response
    request = response.instance_variable_get("@request")
    print red
    print_rest_request(request)
    print "\n"
    print_rest_response(response)
    print reset
  end

  def print_dry_run(opts)
    http_method = opts[:method]
    url = opts[:url]
    params = opts[:params]
    params = opts[:headers][:params] if opts[:headers] && opts[:headers][:params]
    query_string = params.respond_to?(:map) ? URI.encode_www_form(params) : query_string
    if query_string && !query_string.empty?
      url = "#{url}?#{query_string}"
    end
    request_string = "#{http_method.to_s.upcase} #{url}".strip
    payload = opts[:payload]
    print "\n" ,cyan, bold, "DRY RUN\n","==================", "\n\n", reset
    print cyan
    print "Request: ", "\n"
    print reset
    print request_string, "\n"
    print cyan
    if payload
      if payload.is_a?(String)
        begin
          payload = JSON.parse(payload)
        rescue => e
          #payload = "(unparsable) #{payload}"
        end
      end
      print "\n"
      print "JSON: ", "\n"
      print reset
      print JSON.pretty_generate(payload)
    end
    print "\n"
    print reset
  end

  def print_results_pagination(json_response)
    if json_response && json_response["meta"]
      print cyan,"\nViewing #{json_response['meta']['offset'].to_i + 1}-#{json_response['meta']['offset'].to_i + json_response['meta']['size'].to_i} of #{json_response['meta']['total']}\n"
    end
  end

  def required_blue_prompt
    "#{cyan}|#{reset}"
  end
end
