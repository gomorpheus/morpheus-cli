require 'uri'
require 'term/ansicolor'
require 'json'
require 'ostruct'

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
    # todo: replace most usage of this with raise CommandError.new(msg)
    # $stderr.print "#{red}#{msg}#{reset}\n"
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

  def print_results_pagination(json_response, options={})
    # print cyan,"\nViewing #{json_response['meta']['offset'].to_i + 1}-#{json_response['meta']['offset'].to_i + json_response['meta']['size'].to_i} of #{json_response['meta']['total']}\n", reset
    print format_results_pagination(json_response, options)
  end

  def format_results_pagination(json_response, options={})
    # no output for strange, empty data
    if json_response.nil? || json_response.empty?
      return ""
    end
    
    # options = OpenStruct.new(options) # laff, let's do this instead
    color = options.key?(:color) ? options[:color] : cyan
    label = options[:label]
    n_label = options[:n_label]
    # label = n_label if !label && n_label
    message = options[:message] || "Viewing %{start_index}-%{end_index} of %{total} %{label}"
    blank_message = options[:blank_message] || nil # "No %{label} found"

    # support lazy passing of common json_response {"meta": {"size": {25}, "total": 56} }
    # otherwise use the root values given
    meta = OpenStruct.new(json_response)
    if meta.meta
      meta = OpenStruct.new(meta.meta)
    end
    offset, size, total = meta.offset.to_i, meta.size.to_i, meta.total.to_i
    #objects = meta.objects || options[:objects_key] ? json_response[options[:objects_key]] : nil
    #objects ||= meta.instances || meta.servers || meta.users || meta.roles
    #size = objects.size if objects && size == 0
    if total == 0
      total = size
    end
    if total != 1
      label = n_label || label
    end
    out_str = ""
    string_key_values = {start_index: offset + 1, end_index: offset + size, total: total, size: size, offset: offset, label: label}
    if size > 0
      if message
        out_str << message % string_key_values
      end
    else
      if blank_message
        out_str << blank_message % string_key_values
      else
        #out << "No records"
      end
    end
    out = ""
    out << "\n"
    out << color if color
    out << out_str.strip
    out << reset if color
    out << "\n"
    out
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

  def format_dt_dd(label, value, label_width=10, justify="right", do_wrap=true)
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

  # truncate_string truncates a string and appends the suffix "..."
  # @param value [String] the string to pad
  # @param width [Integer] the length to truncate to
  # @param pad_char [String] the character to pad with. Default is ' '
  def truncate_string(value, width, suffix="...")
    value = value.to_s
    # JD: hack alerty.. this sux, but it's a best effort to preserve values containing ascii coloring codes
    #     it stops working when there are words separated by ascii codes, eg. two diff colors
    #     plus this is probably pretty slow...
    uncolored_value = Term::ANSIColor.coloring? ? Term::ANSIColor.uncolored(value.to_s) : value.to_s
    if uncolored_value != value
      trimmed_value = nil
      if uncolored_value.size > width
        if suffix
          trimmed_value = uncolored_value[0..width-(suffix.size+1)] + suffix
        else
          trimmed_value = uncolored_value[0..width-1]
        end
        return value.gsub(uncolored_value, trimmed_value)
      else
        return value
      end
    else
      if value.size > width
        if suffix
          return value[0..width-(suffix.size+1)] + suffix
        else
          return value[0..width-1]
        end
      else
        return value
      end
    end
  end

  # justified returns a left, center, or right aligned string. 
  # @param value [String] the string to pad
  # @param width [Integer] the length to truncate to
  # @param pad_char [String] the character to pad with. Default is ' '
  # @return [String]
  def justify_string(value, width, justify="left", pad_char=" ")
    # JD: hack alert! this sux, but it's a best effort to preserve values containing ascii coloring codes
    value = value.to_s
    uncolored_value = Term::ANSIColor.coloring? ? Term::ANSIColor.uncolored(value.to_s) : value.to_s
    if value.size != uncolored_value.size
      width = width + (value.size - uncolored_value.size)
    end
    if justify == "right"
      return "#{value}".rjust(width, pad_char)
    elsif justify == "center"
      return "#{value}".center(width, pad_char)
    else
      return "#{value}".ljust(width, pad_char)
    end
  end

  def format_table_cell(value, width, justify="left", pad_char=" ", suffix="...")
    #puts "format_table_cell(#{value}, #{width}, #{justify}, #{pad_char.inspect})"
    cell = value.to_s
    cell = truncate_string(cell, width, suffix)
    cell = justify_string(cell, width, justify, pad_char)
    cell
  end

  # as_pretty_table generates a table with aligned columns and truncated values.
  # This can be used in place of TablePrint.tp()
  # @param data [Array] A list of objects to extract the data from.
  # @param columns - [Array of Objects] list of column definitions, A column definition can be a String, Symbol, or Hash
  # @return [String]
  # Usage: puts as_pretty_table(my_objects, [:id, :name])
  #        puts as_pretty_table(my_objects, ["id", "name", {"plan" => "plan.name" }], {color: white})
  #
  def as_pretty_table(data, columns, options={})
    data = [data].flatten
    columns = build_column_definitions(columns)

    table_color = options[:color] || cyan
    cell_delim = options[:delim] || " | "

    header_row = []
    
    columns.each do |column_def|
      header_row << column_def.label
    end

    # generate rows matrix data for the specified columns
    rows = []
    data.each do |row_data|
      row = []
      columns.each do |column_def|
        # r << column_def.display_method.respond_to?(:call) ? column_def.display_method.call(row_data) : get_object_value(row_data, column_def.display_method)
        value = column_def.display_method.call(row_data)        
        row << value
      end
      rows << row
    end

    # all rows (pre-formatted)
    data_matrix = [header_row] + rows
  
    # determine column meta info i.e. width    
    columns.each_with_index do |column_def, column_index|
      # column_def.meta = {
      #   max_value_size: (header_row + rows).max {|row| row[column_index] ? row[column_index].to_s.size : 0 }.size
      # }
      if column_def.fixed_width
        column_def.width = column_def.fixed_width.to_i
      else
        max_value_size = 0
        data_matrix.each do |row|
          v = row[column_index].to_s
          v_size = Term::ANSIColor.coloring? ? Term::ANSIColor.uncolored(v).size : v.size
          if v_size > max_value_size
            max_value_size = v_size
          end
        end

        max_width = (column_def.max_width.to_i > 0) ? column_def.max_width.to_i : nil
        min_width = (column_def.min_width.to_i > 0) ? column_def.min_width.to_i : nil
        if min_width && max_value_size < min_width
          column_def.width = min_width
        elsif max_width && max_value_size > max_width
          column_def.width = max_width
        else
          # expand / contract to size of the value by default
          column_def.width = max_value_size
        end
        #puts "DEBUG: #{column_index} column_def.width:  #{column_def.width}"
      end
    end

    # format header row
    header_cells = []
    columns.each_with_index do |column_def, column_index|
      value = header_row[column_index] # column_def.label
      header_cells << format_table_cell(value, column_def.width, column_def.justify)
    end
    
    # format header spacer row
    h_line = header_cells.collect {|cell| ("-" * cell.size) }.join(cell_delim.gsub(" ", "-"))
    
    # format data rows
    formatted_rows = []
    rows.each_with_index do |row, row_index|
      formatted_row = []
      row.each_with_index do |value, column_index|
        column_def = columns[column_index]
        formatted_row << format_table_cell(value, column_def.width, column_def.justify)
      end
      formatted_rows << formatted_row
    end
    
    

    table_str = ""
    table_str << header_cells.join(cell_delim) + "\n"
    table_str << h_line + "\n"
    formatted_rows.each do |row|
      table_str << row.join(cell_delim) + "\n"
    end

    out = ""
    out << table_color if table_color
    out << table_str
    out << reset if table_color
    out
  end


  # as_description_list() prints a a two column table containing
  # the name and value of a list of descriptions
  # @param columns - [Hash or Array or Hashes] list of column definitions, A column defintion can be a String, Symbol, Hash or Proc
  # @param obj [Object] an object to extract the data from, it is treated like a Hash.
  # @param opts [Map] rendering options for label :justify, :wrap
  # Usage: 
  # print_description_list([:id, :name, :status], my_instance, {})
  #
  def as_description_list(obj, columns, opts={})
    
    columns = build_column_definitions(columns)
    
    #label_width = opts[:label_width] || 10
    max_label_width = 0
    justify = opts.key?(:justify) ? opts[:justify] : "right"
    do_wrap = opts.key?(:wrap) ? !!opts[:wrap] : true
    
    rows = []
    
    columns.flatten.each do |column_def|
      # label, value = extract_label_and_value(column_def, obj, opts)
      label = column_def.label
      # value = get_object_value(obj, column_def.display_method)
      value = column_def.display_method.call(obj)
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

    out = ""
    rows.each do |row|
      value = row[:value].to_s
      if do_wrap
        if value_width && value_width < value.size
          wrap_indent = label_width + 1
          value = wrap(value, value_width, wrap_indent)
        end
      end
      out << format_dt_dd(row[:label], value, label_width, justify) + "\n"
    end
    return out
  end

  # print_description_list() is an alias for `print generate_description_list()`
  def print_description_list(columns, obj, opts={})
    # raise "oh no.. replace with as_description_list()"
    print as_description_list(obj, columns, opts)
  end

  # build_column_definitions constructs an Array of column definitions (OpenStruct)
  # Each column is defined by a label (String), and a display_method (Proc)
  #
  # @columns [Array] list of definitions. A column definition can be a String, Symbol, Proc or Hash
  # @return [Array of OpenStruct] list of column definitions (OpenStruct) like:
  #      [{label: "ID", display_method: 'id'}, {label: "Name", display_method: Proc}]
  # Usage:
  #   build_column_definitions(:id, :name)
  #   build_column_definitions({"Object Id" => 'id'}, :name)
  #   build_column_definitions({"ID" => 'id'}, "name", "plan.name", {status: lambda {|data| data['status'].upcase } })
  #
  def build_column_definitions(*columns)
    # allow passing a single hash instead of an array of hashes
    if columns.size == 1 && columns[0].is_a?(Hash)
      columns = columns[0].collect {|k,v| {(k) => v} }
    else
      columns = columns.flatten.compact
    end
    results = []
    columns.each do |col|
      # determine label
      if col.is_a?(String)
        k = col
        v = col
        build_column_definitions([{(k) => v}]).each do |r|
          results << r if r
        end
      elsif col.is_a?(Symbol)
        k = col.to_s.upcase #.capitalize
        v = col.to_s
        build_column_definitions([{(k) => v}]).each do |r|
          results << r if r
        end
      elsif col.is_a?(Hash)
        column_def = OpenStruct.new
        k, v = col.keys[0], col.values[0]
        if k.is_a?(String)
          column_def.label = k
        elsif k.is_a?(Symbol)
          column_def.label = k
        else
          column_def.label = k.to_s
          # raise "invalid column definition label (#{k.class}) #{k.inspect}. Should be a String or Symbol."
        end

        # determine display_method
        if v.is_a?(String)
          column_def.display_method = lambda {|data| get_object_value(data, v) }
        elsif v.is_a?(Symbol)
          column_def.display_method = lambda {|data| get_object_value(data, v) }
        elsif v.is_a?(Proc)
          column_def.display_method = v
        elsif v.is_a?(Hash) || v.is_a?(OStruct)
          if v[:display_name] || v[:label]
            column_def.label = v[:display_name] || v[:label]
          end
          if v[:display_method]
            if v[:display_method].is_a?(Proc)
              column_def.display_method = v[:display_method]
            else
              # assume v[:display_method] is a String, Symbol
              column_def.display_method = lambda {|data| get_object_value(data, v[:display_method]) }
            end
          else
            # the default behavior is to use the key (undoctored) to find the data
            # column_def.display_method = k
            column_def.display_method = lambda {|data| get_object_value(data, k) }
          end
          
          # other column rendering options
          column_def.justify = v[:justify]
          if v[:max_width]
            column_def.max_width = v[:max_width]
          end
          if v[:min_width]
            column_def.min_width = v[:min_width]
          end
          # tp uses width to behave like max_width
          if v[:width]
            column_def.width = v[:width]
            column_def.max_width = v[:width]
          end
          column_def.wrap = v[:wrap].nil? ? true :  v[:wrap] # only utlized in as_description_list() right now
          
        else
          raise "invalid column definition value (#{v.class}) #{v.inspect}. Should be a String, Symbol, Proc or Hash"
        end        

        # only upcase label for symbols, this is silly anyway, 
        # just pass the exact label (key) that you want printed..
        if column_def.label.is_a?(Symbol)
          column_def.label = column_def.label.to_s.upcase
        end

        results << column_def        

      else
        raise "invalid column definition (#{column_def.class}) #{column_def.inspect}. Should be a String, Symbol or Hash"
      end
      
    end

    return results
  end

  # # @return [Array] [0] is a String representing the column label and Object 
  # def extract_label_and_value(column_def, data, opts={})
  #   # this method shouldn't need options, fix it
  #   # probably some recursive
  #   # this works right now, but it's pretty slow and hacky
  #   capitalize_labels = opts.key?(:capitalize_labels) ? !!opts[:capitalize_labels] : true
  #   label, value = nil, nil
  #   if column_def.is_a?(String)
  #     label = column_def
  #     # value = data[column_def] || data[column_def.to_sym]
  #     value = get_object_value(data, column_def)
  #   elsif column_def.is_a?(Symbol)
  #     label = capitalize_labels ? column_def.to_s.capitalize : column_def.to_s
  #     # value = data[column_def] || data[column_def.to_s]
  #     value = get_object_value(data, column_def)
  #   elsif column_def.is_a?(Hash)
  #     k, v = column_def.keys[0], column_def.values[0]
  #     if v.is_a?(String)
  #       label = k
  #       value = get_object_value(data, v)
  #     elsif v.is_a?(Symbol)
  #       label = capitalize_labels ? k.to_s.capitalize : k.to_s
  #       value = get_object_value(data, v)
  #       # value = data[v] || data[v.to_s]
  #     elsif v.is_a?(Hash)
  #       if v[:display_name]
  #         label = v[:display_name]
  #       else
  #         label = (capitalize_labels && k.is_a?(Symbol)) ? k.to_s.capitalize : k.to_s
  #       end
  #       if v[:display_method]
  #         if v[:display_method].is_a?(Proc)
  #           value = v[:display_method].call(data)
  #         else
  #           value = get_object_value(data, v[:display_method].to_s)
  #         end
  #       else
  #         value = get_object_value(data, v.to_s)
  #       end
  #     elsif v.is_a?(Proc)
  #       label = (capitalize_labels && k.is_a?(Symbol)) ? k.to_s.capitalize : k.to_s
  #       value = v.call(data)
  #     else
  #       raise "invalid column value #{v.class} #{v.inspect}. Should be a String, Symbol, Hash or Proc"
  #     end
  #   else
  #     raise "invalid column #{column_def.class} #{column_def.inspect}. Should be a String, Symbol or Hash"
  #   end
  #   return label, value
  # end

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

  def as_csv(data, columns, opts={})
    out = ""
    delim = opts[:csv_delim] || opts[:delim] || ","
    newline = opts[:csv_newline] || opts[:newline] || "\n"
    include_header = opts[:csv_no_header] ? false : true
    do_quotes = opts[:csv_quotes] || opts[:quotes]
    # allow passing a single hash instead of an array of hashes
    # todo: stop doing this, always pass an array!
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
          # label, value = extract_label_and_value(column_def, obj, opts)
          value = get_object_value(obj, column_def)
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

  def records_as_csv(records, opts={}, default_columns=nil)
    out = ""
    if !records
      #raise "records_as_csv expects records as an Array of objects to render"
      return out
    end
    cols = []
    all_fields = records.first ? records.first.keys : []
    if opts[:include_fields]
      if opts[:include_fields] == 'all' || opts[:include_fields].include?('all')
        cols = all_fields
      else
        cols = opts[:include_fields]
      end
    elsif default_columns
      cols = default_columns
    else
      cols = all_fields
    end
    out << as_csv(records, cols, opts)
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

  def anded_list(items)
    items = items ? items.clone : []
    last_item = items.pop
    if items.empty?
      return "#{last_item}"
    else
      return items.join(", ") + " and #{last_item}"
    end
  end

end
