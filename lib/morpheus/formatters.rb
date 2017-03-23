require 'time'

DEFAULT_TIME_FORMAT = "%x %I:%M %p %Z"

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

def format_duration(start_time, end_time, format="human")
  if !start_time
    return ""
  end
  if end_time.nil? || end_time.empty?
    end_time = Time.now
  end
  start_time = parse_time(start_time)
  end_time = parse_time(end_time)
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

# returns a human readable time duration
# @param seconds - duration in seconds
def format_human_duration(seconds)
  out = ""
  #seconds = seconds.round
  days, hours, minutes = (seconds / (60*60*24)).floor, (seconds / (60*60)).floor, (seconds / (60)).floor
  if days > 365
    out << "#{days.floor} days (more than a year!!)"
  elsif days > 61
    out << "#{days.floor} days (months!)"
  elsif days > 31
    out << "#{days.floor} days (over a month)"
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
    value = data[key] || data[key.to_sym]
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
        # field = field.to_s
        if field.include?(".")
          # could do this instead...
          # namespaces = field.split(".")
          # cur_data = data
          # namespaces.each
          #   if index != namespaces.length - 1
          #     cur_data[ns] ||= {}
          #   else
          #     cur_data[ns] = get_object_value(new_data, field)
          #   end
          # end
          namespaces = field.split(".")
          cur_data = data
          cur_filtered_data = my_data
          namespaces.each_with_index do |ns, index|
            if index != namespaces.length - 1
              if cur_data
                cur_data = cur_data[ns]
              else
                cur_data = nil
              end
              cur_filtered_data[ns] ||= {}
              cur_filtered_data = cur_filtered_data[ns]
            else
              if cur_data.respond_to?("[]")
                cur_filtered_data[ns] = cur_data[ns]
              else
                cur_filtered_data[ns] = nil
              end
            end
          end
        else
          my_data[field] = data[field]
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
