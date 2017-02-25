require 'rest_client'

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
        opts = {timeout: 30}.merge(options)

        unless ssl_verification_enabled?
          opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
        end

        opts[:headers] ||= {}
        opts[:headers][:user_agent] ||= self.user_agent

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
