require 'time'

# returns an instance of Time
def parse_time(dt)
  if dt.nil? || dt == '' || dt.to_i == 0
    return nil
  elsif dt.is_a?(Time)
    return dt
  elsif dt.is_a?(String)
    return Time.parse(dt)
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
  format = options[:format] || "%x %I:%M %p %Z"
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

def display_appliance(name, url)
  "#{name} - #{url}"
end

def iso8601(dt)
  dt.instance_of(Time) ? dt.iso8601 : "#{dt}"
end

# get_data_value returns a value within a Hash like object
# Usage: get_data_value(host, "plan.name")
def get_data_value(data, key)
  value = nil
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
    value = data[key] # || data[key.to_sym]
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
      # allow extracting dot pathed fields, just like get_data_value
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
          #     cur_data[ns] = get_data_value(new_data, field)
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
