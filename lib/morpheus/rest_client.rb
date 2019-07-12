require 'rest-client'
require 'uri'

module Morpheus
  # A wrapper around rest_client so we can more easily deal with passing options (like turning on/off SSL verification)
  class RestClient

    class << self

      def user_agent
        if !@user_agent
          begin
            @user_agent = "morpheus-cli #{Morpheus::Cli::VERSION}"
            @user_agent = "#{@user_agent} (#{::RestClient::Platform.architecture}) #{::RestClient::Platform.ruby_agent_version}"
          rescue => e
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
          query_string = URI.encode_www_form(query_string)
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

      private

      # unused eh?
      def build_request_args(url, method, payload)
        args = {url: url, method: method, payload: payload}
        unless ssl_verification_enabled?
          args[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
        end
        args
      end
    end
  end
end
