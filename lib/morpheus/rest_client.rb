require 'rest-client'
require 'uri'

module Morpheus
  # A wrapper around rest_client so we can more easily deal with passing options (like turning on/off SSL verification)
  class RestClient

    class << self

      def user_agent
        if !defined?(@user_agent) || @user_agent.nil?
          begin
            @user_agent = "morpheus-cli #{Morpheus::Cli::VERSION}"
            @user_agent = "#{@user_agent} (#{::RestClient::Platform.architecture}) #{::RestClient::Platform.ruby_agent_version}"
          rescue
          end
        end
        return @user_agent
      end

      def execute(options)
        default_opts = {}
        # only read requests get default 30 second timeout.
        if options[:method] == :get || options[:method] == :head
          default_opts[:timeout] = 30
        end
        opts = default_opts.merge(options)
        unless ssl_verification_enabled?
          opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
        end

        opts[:headers] ||= {}
        opts[:headers][:user_agent] ||= self.user_agent

        # serialize params ourselves, this way we get arrays without the [] suffix
        params = nil
        if opts[:params] && !opts[:params].empty?
          params = opts.delete(:params)
        elsif opts[:headers] && opts[:headers][:params]
          # params inside headers for restclient reasons..
          params = opts[:headers].delete(:params)
        elsif opts[:query] && !opts[:query].empty?
          params = opts.delete(:query)
        end
        query_string = params
        if query_string.respond_to?(:map)
          if options[:grails_params] != false
            query_string = grails_params(query_string)
          end
          query_string = URI.encode_www_form(query_string)
        end
        # grails expects dot notation in body params
        if opts[:method] == :post || opts[:method] == :put
          if opts[:headers]['Content-Type'].nil? || opts[:headers]['Content-Type'] == 'application/x-www-form-urlencoded' || opts[:headers]['Content-Type'] == 'multipart/form-data'
            if opts[:payload].respond_to?(:map)
              if opts[:grails_params] != false
                # puts "grailsifying it!"
                opts[:payload] = grails_params(opts[:payload])
              end
            end
          end
        end
        if query_string && !query_string.empty?
          opts[:url] = "#{opts[:url]}?#{query_string}"
        end

        ::RestClient::Request.execute opts
      end

      def post(url, payload)
        execute url: url, payload: payload, method: :post
      end

      def ssl_verification_enabled?
        begin
          @@ssl_verification_enabled.nil? ? true : @@ssl_verification_enabled
        rescue
          @@ssl_verification_enabled = true
        end
      end

      def enable_ssl_verification=(verify)
        @@ssl_verification_enabled = verify
      end

      def grails_params(data, context=nil)
        params = {}
        data.each do |k,v|
          if v.is_a?(Hash)
            params.merge!(grails_params(v, context ? "#{context}.#{k.to_s}" : k))
          else
            if context
              params["#{context}.#{k.to_s}"] = v
            else
              params[k] = v
            end
          end
        end
        return params
      end

    end
  end
end
