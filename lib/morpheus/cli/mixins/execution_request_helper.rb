require 'morpheus/cli/mixins/print_helper'
# Mixin for Morpheus::Cli command classes
# Provides refreshing execution-request records by unique id (uuid)
module Morpheus::Cli::ExecutionRequestHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def api_client
    raise "#{self.class} has not defined @api_client" if @api_client.nil?
    @api_client
  end

  def execution_request_interface
    # get_interface('execution_request')
    api_client.execution_request
  end

  # refresh execution request until it is finished
  # returns json response data of the last execution request when status reached 'completed' or 'failed'
  def wait_for_execution_request(execution_request_id, options={}, print_output = true)
    refresh_interval = 10
    if options[:refresh_interval].to_i > 0
      refresh_interval = options[:refresh_interval]
    end
    execution_request = execution_request_interface.get(execution_request_id)['executionRequest']
    refresh_display_seconds = refresh_interval % 1.0 == 0 ? refresh_interval.to_i : refresh_interval
    # unless options[:quiet]
    #   print cyan, "Execution request has not yet finished. Refreshing every #{refresh_display_seconds} seconds...", "\n", reset
    # end
    while (options[:waiting_status] || ['new', 'pending']).include?(execution_request['status']) do
      sleep(refresh_interval)
      execution_request = execution_request_interface.get(execution_request_id)['executionRequest']
    end
    if print_output && options[:quiet] != true
      if execution_request['stdErr'].to_s.strip != '' && execution_request['stdErr'] != "stdin: is not a tty\n"
        print_h2 "Error"
        print execution_request['stdErr'].to_s.strip, reset, "\n"
      end
      if execution_request['stdOut'].to_s.strip != ''
        print_h2 "Output"
        print execution_request['stdOut'].to_s.strip, reset, "\n"
      end
      print reset, "\n"
    end
    return execution_request
  end

end
