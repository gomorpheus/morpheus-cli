require 'uri'
require 'term/ansicolor'
require 'json'

module Morpheus::Cli::PrintHelper

  def self.included(klass)
    klass.send :include, Term::ANSIColor
  end

  def self.terminal_width
    @@terminal_width ||= 80
  end

  def self.terminal_width=(v)
    if v.nil? || v.to_i == 0
      @@terminal_width = nil
    else
      @@terminal_width = v.to_i
    end
    @@terminal_width
  end

  def print_red_alert(msg)
    print "#{red}#{msg}#{reset}\n"
  end

  def print_yellow_warning(msg)
    print "#{yellow}#{msg}#{reset}\n"
  end

  def print_green_success(msg)
    print "#{green}#{msg}#{reset}\n"
  end

  # print_h1 prints a header title and optional subtitles
  # Output:
  #
  # title - subtitle1, subtitle2
  # ==================
  #
  def print_h1(title, subtitles=[], color=cyan)
    #print "\n" ,color, bold, title, (subtitles.empty? ? "" : " - #{subtitles.join(', ')}"), "\n", "==================", reset, "\n\n"
    subtitles = subtitles.flatten
    out = ""
    out << "\n"
    out << "#{color}#{bold}#{title}#{reset}"
    if !subtitles.empty?
      out << "#{color} - #{subtitles.join(', ')}#{reset}"
    end
    out << "\n"
    out << "#{color}#{bold}==================#{reset}"
    out << "\n\n"
    out << reset
    print out
  end

  def print_h2(title, subtitles=[], color=cyan)
    #print "\n" ,color, bold, title, (subtitles.empty? ? "" : " - #{subtitles.join(', ')}"), "\n", "---------------------", reset, "\n\n"
    subtitles = subtitles.flatten
    out = ""
    out << "\n"
    out << "#{color}#{bold}#{title}#{reset}"
    if !subtitles.empty?
      out << "#{color} - #{subtitles.join(', ')}#{reset}"
    end
    out << "\n"
    out << "#{color}---------------------#{reset}"
    out << "\n\n"
    out << reset
    print out
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
    print_h1 "DRY RUN"
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
      print cyan,"\nViewing #{json_response['meta']['offset'].to_i + 1}-#{json_response['meta']['offset'].to_i + json_response['meta']['size'].to_i} of #{json_response['meta']['total']}\n", reset
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
      percent = ((used_value.to_f / max_value.to_f) * 100)
    end
    percent_label = ((used_value.nil? || max_value.to_f == 0.0) ? "n/a" : "#{percent.round(2)}%").rjust(6, ' ')
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
      bar_display = white + "[" + rainbow_bar + white + "]" + " #{cur_rainbow_color}#{percent_label}#{reset}"
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
    label_width = opts[:label_width] || 10
    out = ""
    if stats.nil? || stats.empty?
      out << cyan + "No data." +  "\n" + reset
      print out
      return
    end
    opts[:include] ||= [:memory, :storage, :cpu]
    if opts[:include].include?(:cpu)
      cpu_usage = (stats['usedCpu'] || stats['cpuUsage'])
      out << cyan + "CPU".rjust(label_width, ' ') + ": " + generate_usage_bar(cpu_usage.to_f, 100)  + "\n"
    end
    if opts[:include].include?(:memory)
      out << cyan + "Memory".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['usedMemory'], stats['maxMemory']) + cyan + Filesize.from("#{stats['usedMemory']} B").pretty.strip.rjust(15, ' ')           + " / " + Filesize.from("#{stats['maxMemory']} B").pretty.strip.ljust(15, ' ')  + "\n"
    end
    if opts[:include].include?(:storage)
      out << cyan + "Storage".rjust(label_width, ' ') + ": " + generate_usage_bar(stats['usedStorage'], stats['maxStorage']) + cyan + Filesize.from("#{stats['usedStorage']} B").pretty.strip.rjust(15, ' ') + " / " + Filesize.from("#{stats['maxStorage']} B").pretty.strip.ljust(15, ' ') + "\n"
    end
    print out
  end

  def print_available_options(option_types)
    option_lines = option_types.collect {|it| "\t-O #{it['fieldContext'] ? it['fieldContext'] + '.' : ''}#{it['fieldName']}=\"value\"" }.join("\n")
    puts "Available Options:\n#{option_lines}\n\n"
  end

  def dd_dt(label, value, label_width=10, justify="right", do_wrap=true)
    # JD: uncomment next line to do away with justified labels
    # label_width, justify = 0, "none"
    out = ""
    value = value.to_s
    if do_wrap && value && Morpheus::Cli::PrintHelper.terminal_width
      value_width = Morpheus::Cli::PrintHelper.terminal_width - label_width
      if value_width > 0 && value.to_s.size > value_width
        wrap_indent = label_width + 1 # plus 1 needs to go away
        value = wrap(value, value_width, wrap_indent)
      end
    end
    if justify == "right"
      out << "#{label}:".rjust(label_width, ' ') + " #{value}" 
    elsif justify == "left"
      out << "#{label}:".ljust(label_width, ' ') + " #{value}" 
    else
      # default is none
      out << "#{label}:" + " #{value}" 
    end
    out
  end

  # generate_description_list() prints a a two column table containing
  # the name and value of a list of descriptions
  # @param columns - [Hash or Array or Hashes] list of column definitions, A column defintion can be a String, Symbol, Hash or Proc
  # @param data [Object] an object to extract the data from, it is treated like a Hash.
  # @param opts [OptionParser] the option parser object being constructed
  # Usage: 
  # print_description_list([:id, :name, :status], my_instance, {})
  #
  def generate_description_list(columns, data, opts={})
    out = ""
    #label_width = opts[:label_width] || 10
    max_label_width = 0
    justify = opts.key?(:justify) ? opts[:justify] : "right"
    do_wrap = opts.key?(:wrap) ? !!opts[:wrap] : true
    rows = []
    # allow passing a single hash instead of an array of hashes
    if columns.is_a?(Hash)
      columns = columns.collect {|k,v| {(k) => v} } 
    end
    columns.flatten.each do |column_def|
      label, value = extract_description_value(column_def, data, opts)
      if label.size > max_label_width
        max_label_width = label.size
      end
      rows << {label: label, value: value}
    end
    label_width = max_label_width + 1 # for a leading space ' ' ..ew
    value_width = nil
    if Morpheus::Cli::PrintHelper.terminal_width
      value_width = Morpheus::Cli::PrintHelper.terminal_width - label_width
    end
    rows.each do |row|
      value = row[:value].to_s
      if do_wrap
        if value_width && value_width < value.size
          wrap_indent = label_width + 1
          value = wrap(value, value_width, wrap_indent)
        end
      end
      out << dd_dt(row[:label], value, label_width, justify) + "\n"
    end
    return out
  end

  # print_description_list() is an alias for `print generate_description_list()`
  def print_description_list(columns, data, opts={})
    print generate_description_list(columns, data, opts)
  end

  def extract_description_value(column_def, data, opts={})
    # this method shouldn't need options, fix it
    capitalize_labels = opts.key?(:capitalize_labels) ? !!opts[:capitalize_labels] : true
    label, value = nil, nil
    if column_def.is_a?(String)
      label = column_def
      # value = data[column_def] || data[column_def.to_sym]
      value = get_data_value(data, column_def)
    elsif column_def.is_a?(Symbol)
      label = capitalize_labels ? column_def.to_s.capitalize : column_def.to_s
      # value = data[column_def] || data[column_def.to_s]
      value = get_data_value(data, column_def)
    elsif column_def.is_a?(Hash)
      k, v = column_def.keys[0], column_def.values[0]
      if v.is_a?(String)
        label = k
        value = get_data_value(data, v)
      elsif v.is_a?(Symbol)
        label = capitalize_labels ? k.to_s.capitalize : k.to_s
        value = get_data_value(data, v)
        # value = data[v] || data[v.to_s]
      elsif v.is_a?(Hash)
        if v[:display_name]
          label = v[:display_name]
        else
          label = (capitalize_labels && k.is_a?(Symbol)) ? k.to_s.capitalize : k.to_s
        end
        if v[:display_method]
          if v[:display_method].is_a?(Proc)
            value = v[:display_method].call(data)
          else
            value = get_data_value(data, v[:display_method].to_s)
          end
        else
          value = get_data_value(data, v.to_s)
        end
      elsif v.is_a?(Proc)
        label = (capitalize_labels && k.is_a?(Symbol)) ? k.to_s.capitalize : k.to_s
        value = v.call(data)
      else
        raise "extract_description_value() invalid column value #{v.class} #{v.inspect}. Should be a String, Symbol, Hash or Proc"
      end
    else
      raise "extract_description_value() invalid column #{column_def.class} #{column_def.inspect}. Should be a String, Symbol or Hash"
    end
    return label, value
  end

  def wrap(s, width, indent=0)
    out = s
    if s.size > width
      if indent > 0
        out = s.gsub(/(.{1,#{width}})(\s+|\Z)/, "#{' ' * indent}\\1\n").strip
      else
        out = s.gsub(/(.{1,#{width}})(\s+|\Z)/, "\\1\n")
      end
    else
      return s
    end
  end

  def format_boolean(v)
    !!v ? 'Yes' : 'No'
  end

  def quote_csv_value(v)
    '"' + v.to_s.gsub('"', '""') + '"'
  end

  def as_csv(columns, data, opts={})
    out = ""
    delim = opts[:csv_delim] || opts[:delim] || ","
    newline = opts[:csv_newline] || opts[:newline] || "\n"
    include_header = opts[:csv_no_header] ? false : true
    do_quotes = opts[:csv_quotes] || opts[:quotes]
    # allow passing a single hash instead of an array of hashes
    if columns.is_a?(Hash)
      columns = columns.collect {|k,v| {(k) => v} }
    end
    columns = columns.flatten.compact
    data_array = [data].flatten.compact
    if include_header
      headers = columns.collect {|column_def| column_def.is_a?(Hash) ? column_def.keys[0].to_s : column_def.to_s }
      if do_quotes
        headers = headers.collect {|it| quote_csv_value(it) }
      end
      out << headers.join(delim)
      out << newline
    end
    lines = []
    data_array.each do |obj|
      if obj
        cells = []
        columns.each do |column_def|
          # this is silly, fix it
          label, value = extract_description_value(column_def, obj, opts)
          if do_quotes
            cells << quote_csv_value(value)
          else
            cells << value.to_s
          end
        end
      end
      line = cells.join(delim)
      lines << line
    end
    out << lines.join(newline)
    #out << delim
    out
  end

  def as_json(data, options={})
    out = ""
    if !data
      return "null" # "No data"
    end
    
    # include_fields = options[:include_fields]
    # if include_fields
    #   json_fields_for = options[:json_fields_for] || options[:fields_for] || options[:root_field]
    #   if json_fields_for && data[json_fields_for]
    #     data[json_fields_for] = filtered_data(data[json_fields_for], include_fields)
    #   else
    #     data = filtered_data(data, include_fields)
    #   end
    # end
    do_pretty = options.key?(:pretty_json) ? options[:pretty_json] : true
    if do_pretty
      out << JSON.pretty_generate(data)
    else
      out << JSON.fast_generate(data)
    end
    #out << "\n"
    out
  end

  # @deprecated
  def generate_pretty_json(data, options={})
    as_json(data, options)
  end

end
