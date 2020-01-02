require 'time'
require 'filesize'
require 'money'

DEFAULT_TIME_FORMAT = "%x %I:%M %p"

# returns an instance of Time
def parse_time(dt, format=nil)
  if dt.nil? || dt == '' || dt.to_i == 0
    return nil
  elsif dt.is_a?(Time)
    return dt
  elsif dt.is_a?(String)
    result = nil
    err = nil
    begin
      result = Time.parse(dt)
    rescue => e
      err = e
    end
    if !result
      format ||= DEFAULT_TIME_FORMAT
      if format
        begin
          result = Time.strptime(dt, format)
        rescue => e
          err = e
        end
      end
    end
    if result
      return result
    else
      raise "unable to parse time '#{dt}'. #{err}"
    end
    
  elsif dt.is_a?(Numeric)
    return Time.at(dt)
  else
    raise "bad argument type for parse_time() #{dt.class} #{dt.inspect}"
  end
end

def format_dt(dt, options={})
  dt = parse_time(dt)
  return "" if dt.nil?
  if options[:local]
    dt = dt.getlocal
  end
  format = options[:format] || DEFAULT_TIME_FORMAT
  return dt.strftime(format)
end

def format_local_dt(dt, options={})
  format_dt(dt, {local: true}.merge(options))
end

def format_date(dt, options={})
  format_dt(dt, options.merge({local: true}))
end

def format_local_date(dt, options={})
  format_dt(dt, {local: true, format: "%x"}.merge(options))
end

def format_dt_as_param(dt)
  dt = dt.getutc
  format_dt(dt, {format: "%Y-%m-%d %X"})
end

def format_duration(start_time, end_time=nil, format="human")
  if !start_time
    return ""
  end
  start_time = parse_time(start_time)
  if end_time
    end_time = parse_time(end_time)
  else
    end_time = Time.now
  end
  seconds = (end_time - start_time).abs
  format_duration_seconds(seconds, format)
end

def format_duration_seconds(seconds, format="human")
  seconds = seconds.abs
  out = ""
  # interval = Math.abs(interval)
  if format == "human"
    out = format_human_duration(seconds)
  elsif format
    interval_time = Time.mktime(0) + seconds
    out = interval_time.strftime(format)
  else
    interval_time = Time.mktime(0) + seconds
    out = interval_time.strftime("%H:%M:%S")
  end
  out
end

def format_duration_milliseconds(milliseconds, format="human", ms_threshold=1000)
  out = ""
  milliseconds = milliseconds.abs.to_i
  if ms_threshold && ms_threshold > milliseconds
    out = "#{milliseconds}ms"
  else
    out = format_duration_seconds((milliseconds.to_f / 1000).floor, format)
  end
  out
end

# returns a human readable time duration
# @param seconds - duration in seconds
def format_human_duration(seconds)
  out = ""
  #seconds = seconds.round
  days, hours, minutes = (seconds / (60*60*24)).floor, (seconds / (60*60)).floor, (seconds / (60)).floor
  if days > 365
    out << "#{days.floor} days"
  elsif days > 61
    out << "#{days.floor} days"
  elsif days > 31
    out << "#{days.floor} days"
  elsif days > 0
    if days.floor == 1
      out << "1 day"
    else
      out << "#{days.floor} days"
    end
  elsif hours > 1
    if hours == 1
      out << "1 hour"
    else
      out << "#{hours.floor} hours"
    end
  elsif minutes > 1
    if minutes == 1
      out << "1 minute"
    else
      out << "#{minutes.floor} minutes"
    end
  elsif seconds > 0 && seconds < 1
    ms = (seconds.to_f * 1000).to_i
    out << "#{ms}ms"
  else
    seconds = seconds.floor
    if seconds == 1
      out << "1 second"
    else
      out << "#{seconds} seconds"
    end
  end
  out
end

def display_appliance(name, url)
  "#{name} - #{url}"
end

def iso8601(dt)
  dt.instance_of(Time) ? dt.iso8601 : "#{dt}"
end

# get_object_value returns a value within a Hash like object
# Usage: get_object_value(host, "plan.name")
def get_object_value(data, key)
  value = nil
  if key.is_a?(Proc)
    return key.call(data)
  end
  key = key.to_s
  if key.include?(".")
    namespaces = key.split(".")
    value = data
    namespaces.each do |ns|
      if value.respond_to?("key?")
        if value.key?(ns.to_s)
          value = value[ns]
        elsif value.key?(ns.to_sym)
          value = value[ns.to_sym]
        else
          value = nil
        end
      else
        value = nil
      end
    end
  else
    # value = data.key?(key) ? data[key] : data[key.to_sym]
    if data.respond_to?("key?")
      if data.key?(key.to_s)
        value = data[key.to_s]
      elsif data.key?(key.to_sym)
        value = data[key.to_sym]
      end
    end
  end
  return value
end

# filter_data filters Hash-like data to only the specified fields
# To specify fields of child objects, use a "."
# Usage: filter_data(instance, ["id", "name", "plan.name"])
def filter_data(data, include_fields=nil, exclude_fields=nil)
  if !data
    return data
  elsif data.is_a?(Array)
    new_data = data.collect { |it| filter_data(it, include_fields, exclude_fields) }
    return new_data
  elsif data.is_a?(Hash)
    if include_fields
      #new_data = data.select {|k, v| include_fields.include?(k.to_s) || include_fields.include?(k.to_sym) }
      # allow extracting dot pathed fields, just like get_object_value
      my_data = {}
      include_fields.each do |field|
        if field.nil?
          next
        end
        field = field.to_s
        if field.empty?
          next
        end

        # supports "field as Label"
        field_key = field.strip
        field_label = field_key

        if field.index(/\s+as\s+/)
          field_key, field_label = field.split(/\s+as\s+/)
          if !field_label
            field_label = field_key
          end
        end

        if field.include?(".")
          #if field.index(/\s+as\s+/)
          if field_label != field_key
            # collapse to a value
            my_data[field_label] = get_object_value(data, field_key)
          else
            # keep the full object structure
            namespaces = field.split(".")
            cur_data = data
            cur_filtered_data = my_data
            namespaces.each_with_index do |ns, index|
              if index != namespaces.length - 1
                if cur_data && cur_data.respond_to?("key?")
                  cur_data = cur_data.key?(ns) ? cur_data[ns] : cur_data[ns.to_sym]
                else
                  cur_data = nil
                end
                cur_filtered_data[ns] ||= {}
                cur_filtered_data = cur_filtered_data[ns]
              else
                if cur_data && cur_data.respond_to?("key?")
                  cur_filtered_data[ns] = cur_data.key?(ns) ? cur_data[ns] : cur_data[ns.to_sym]
                else
                  cur_filtered_data[ns] = nil
                end
              end
            end
          end
        else
          #my_data[field] = data[field] || data[field.to_sym]
          my_data[field_label] = data.key?(field_key) ? data[field_key] : data[field_key.to_sym]
        end
      end
      return my_data
    elsif exclude_fields
      new_data = data.reject {|k, v| exclude_fields.include?(k.to_s) || exclude_fields.include?(k.to_sym) }
      return new_data
    end
  else
    return data # .clone
  end
end

def format_bytes(bytes, units="B")
  out = ""
  if bytes
    if bytes < 1024 && units == "B"
      out = "#{bytes.to_i} B"
    else
      out = Filesize.from("#{bytes} #{units}").pretty.strip
    end
  end
  return out
end

# returns bytes in an abbreviated format
# eg. 3.1K instead of 3.10 KiB
def format_bytes_short(bytes)
  out = format_bytes(bytes)
  if out.include?(" ")
    val, units = out.split(" ")
    val = val.to_f
    # round to 0 or 1 decimal point
    if val % 1 == 0
      val = val.round(0).to_s
    else
      val = val.round(1).to_s
    end
    # K instead of KiB
    units = units[0].chr
    out = "#{val}#{units}"
  end
  return out
end

def no_colors(str)
  str.to_s.gsub /\e\[\d+m/, ""
end

def format_number(n, opts={})
  delim = opts[:delimiter] || ','
  out = ""
  parts = n.to_s.split(".")
  whole_number = parts[0]
  decimal = parts[1] ? parts[1..-1].join('.') : nil
  i = 0
  whole_number.reverse.each_char do |c|
    out = (i > 0 && i % 3 == 0) ? "#{c}#{delim}#{out}" : "#{c}#{out}"
    i+= 1
  end
  if decimal
    out << "." + decimal
  end
  return out
end

def currency_sym(currency)
  Money::Currency.new((currency || 'usd').to_sym).symbol
end

# returns currency amount formatted like "$4,5123.00". 0.00 is formatted as "$0"
# this is not ideal
def format_money(amount, currency='usd')
  if amount.to_f == 0
    return currency_sym(currency).to_s + "0"
  else
    rtn = amount.to_f.round(2).to_s
    if rtn.index('.').nil?
      rtn += '.00'
    elsif rtn.split('.')[1].length < 2
      rtn = rtn + (['0'] * (2 - rtn.split('.')[1].length) * '')
    end
    dollars,cents = rtn.split(".")
    currency_sym(currency).to_s + format_number(dollars.to_i) + "." + cents
  end
end
