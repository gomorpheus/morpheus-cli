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

# returns
def format_dt_as_param(dt)
	dt = dt.getutc
	format_dt(dt, {format: "%Y-%m-%d %X"})
end
