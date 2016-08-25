require 'time'

  
def format_dt(dt, options={})
  if dt.nil? || dt == '' || dt.to_i == 0
    return 'n/a'
  elsif dt.is_a?(Time)
    dt = dt
  elsif dt.is_a?(String)
    dt = Time.parse(dt)
  elsif dt.is_a?(Numeric)
    dt = Time.at(dt)
  else
    raise "bad argument type for format_dt() #{dt.class} #{dt.inspect}"
  end

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
