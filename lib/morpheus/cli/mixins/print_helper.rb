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


  # shows cyan, yellow, red progress bar where 50% looks like [|||||     ]
  # todo: render units used / available here too maybe
  def generate_usage_bar(used_value, max_value, opts={})
    rainbow = opts[:rainbow] != false
    max_bars = opts[:max_bars] || 50
    out = ""
    bars = []
    
    percent = 0
    if max_value.to_i == 0
      percent = 0
    else
      percent = ((used_value.to_f / max_value.to_f) * 100).round(2)
    end
    percent_label = (used_value.nil? || max_value.to_f == 0.0) ? "n/a" : "#{percent}%"
    bar_display = ""
    if percent > 100
      max_bars.times { bars << "|" }
      # percent = 100
    else
      n_bars = ((percent / 100.0) * max_bars).ceil
      n_bars.times { bars << "|" }
    end

    if rainbow
      rainbow_bar = ""
      cur_rainbow_color = white
      bars.each_with_index {|bar, i|
        reached_percent = (i / max_bars.to_f) * 100
        new_bar_color = cur_rainbow_color
        if reached_percent > 80
          new_bar_color = red
        elsif reached_percent > 50
          new_bar_color = yellow
        elsif reached_percent > 10
          new_bar_color = cyan
        end
        if cur_rainbow_color != new_bar_color
          cur_rainbow_color = new_bar_color
          rainbow_bar << cur_rainbow_color
        end
        rainbow_bar << bar
      }
      padding = max_bars - bars.size
      if padding > 0
        padding.times { rainbow_bar << " " }
        #rainbow_bar <<  " " * padding
      end
      rainbow_bar << reset
      bar_display = white + "[" + rainbow_bar + white + "]" + " #{percent_label}" + reset
      out << bar_display
    else
      bar_color = cyan
      if percent > 80
        bar_color = red
      elsif percent > 50
        bar_color = yellow
      end
      bar_display = white + "[" + bar_color + bars.join.ljust(max_bars, ' ') + white + "]" + " #{percent_label}" + reset
      out << bar_display
    end
    
    return out
  end

  def print_stats_usage(stats, opts={})
    if opts[:include].nil? || opts[:include].include?(:memory)
      print cyan, "Memory:".ljust(10, ' ')  + generate_usage_bar(stats['usedMemory'], stats['maxMemory']).strip.ljust(75, ' ') + Filesize.from("#{stats['usedMemory']} B").pretty.strip.rjust(15, ' ')           + " / " + Filesize.from("#{stats['maxMemory']} B").pretty.strip.ljust(15, ' ')  + "\n"
    end
    if opts[:include].nil? || opts[:include].include?(:storage)
      print cyan, "Storage:".ljust(10, ' ') + generate_usage_bar(stats['usedStorage'], stats['maxStorage']).strip.ljust(75, ' ') + Filesize.from("#{stats['usedStorage']} B").pretty.strip.rjust(15, ' ') + " / " + Filesize.from("#{stats['maxStorage']} B").pretty.strip.ljust(15, ' ') + "\n"
    end
    if opts[:include].nil? || opts[:include].include?(:cpu)
      print cyan, "CPU:".ljust(10, ' ')  + generate_usage_bar(stats['usedCpu'].to_f * 100, 100).strip.ljust(75, ' ') + "\n"
    end
  end

end
