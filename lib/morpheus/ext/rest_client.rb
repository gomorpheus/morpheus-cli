# this does some monkey patching of third party RestClient
# to modify the logging output a bit
require 'rest-client'

module RestClient  
  class Request

    def log_request
      begin
        return unless RestClient.log
        out = []
        # out << "RestClient.#{method} #{redacted_url.inspect}"
        out << "#{method.to_s.upcase} #{redacted_url.inspect}"
        out << payload.short_inspect if payload
        out << processed_headers.to_a.sort.map { |(k, v)| [k.inspect, v.inspect].join("=>") }.join(", ")
        RestClient.log << out.join(', ') + "\n"
      rescue => ex
        # something went wrong, wrong gem version maybe...above is from rest-client 2.0.2
        # do it the old way
        super
      end
    end
=begin
    def log_response res
      return unless RestClient.log
      size = if @raw_response
               File.size(@tf.path)
             else
               res.body.nil? ? 0 : res.body.size
             end

      RestClient.log << "# => #{res.code} #{res.class.to_s.gsub(/^Net::HTTP/, '')} | #{(res['Content-type'] || '').gsub(/;.*$/, '')} #{size} bytes\n"
    end
=end
  end
end
