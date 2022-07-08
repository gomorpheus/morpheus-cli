require 'morpheus/cli/mixins/print_helper'
# Mixin for Morpheus::Cli command classes
# Provides refreshing job execution records by id
module Morpheus::Cli::JobsHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
    # klass.send :include, Morpheus::Cli::ProcessesHelper
  end

  def api_client
    raise "#{self.class} has not defined @api_client" if @api_client.nil?
    @api_client
  end

  def jobs_interface
    # get_interface('jobs')
    api_client.jobs
  end

  def get_process_event_data(process_or_event)
    {
        id: process_or_event['id'],
        description: process_or_event['description'] || (process_or_event['refType'] == 'instance' ? process_or_event['displayName'] : (process_or_event['processTypeName'] || '').capitalize),
        start_date: format_local_dt(process_or_event['startDate']),
        created_by: process_or_event['createdBy'] ? process_or_event['createdBy']['displayName'] : '',
        duration: format_human_duration((process_or_event['duration'] || process_or_event['statusEta'] || 0) / 1000.0),
        status: format_job_status(process_or_event['status']),
        error: process_or_event['message'] || process_or_event['error'],
        output: process_or_event['output'],
    }
  end

  # both process and process events
  def print_process_events(events, options={})
    # event_columns = [:id, :description, :start_date, :created_by, :duration, :status, :error, :output]
    event_columns = {
          "ID" => lambda {|it| it[:id]},
          "Description" => lambda {|it| it[:description]},
          "Start Date" => lambda {|it| it[:start_date]},
          "Created By" => lambda {|it| it[:created_by]},
          "Duration" => lambda {|it| it[:duration]},
          "Status" => lambda {|it| it[:status]},
          "Error" => lambda {|it| options[:details] ? it[:error] : truncate_string(it[:error], 32) },
          "Output" => lambda {|it| options[:details] ? it[:output] : truncate_string(it[:output], 32) }
      }
    print as_pretty_table(events.collect {|it| get_process_event_data(it)}, event_columns.upcase_keys!, options)
  end

  def print_job_execution(job_execution, options)
    process = job_execution['process']
    print cyan
    description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Job" => lambda {|it| it['job'] ? it['job']['name'] : ''},
        "Job Type" => lambda {|it| it['job'] && it['job']['type'] ? (it['job']['type']['code'] == 'morpheus.workflow' ? 'Workflow' : 'Task') : ''},
        # "Description" => lambda {|it| it['description'] || (it['job'] ? it['job']['description'] : '') },
        "Start Date" => lambda {|it| format_local_dt(it['startDate'])},
        "ETA/Time" => lambda {|it| it['duration'] ? format_human_duration(it['duration'] / 1000.0) : ''},
        "Status" => lambda {|it| format_job_status(it['status'])},
        #"Output" => lambda {|it| it['process'] && (it['process']['output']) ?(it['process']['output']).to_s.strip : ''},
        #"Error" => lambda {|it| it['process'] && (it['process']['message'] || it['process']['error']) ? red + (it['process']['message'] || it['process']['error']).to_s.strip + cyan : ''},
        "Created By" => lambda {|it| it['createdBy'].nil? ? '' : it['createdBy']['displayName'] || it['createdBy']['username']}
    }
    print_description_list(description_cols, job_execution, options)

    if process
      process_data = get_process_event_data(process)
      print_h2 "Process Details"
      process_description_cols = {
          "Process ID" => lambda {|it| it[:id]},
          "Description" => lambda {|it| it[:description]},
          "Start Date" => lambda {|it| it[:start_date]},
          "Created By" => lambda {|it| it[:created_by]},
          "Duration" => lambda {|it| it[:duration]},
          "Status" => lambda {|it| it[:status]}
      }
      print_description_list(process_description_cols, process_data, options)

      if process_data[:output] && process_data[:output].strip.length > 0
        print_h2 "Output"
        print process['output']
      end
      if process_data[:error] && process_data[:error].strip.length > 0
        print_h2 "Error"
        print process['message'] || process['error']
        print reset,"\n"
      end
      

      if process['events'] && !process['events'].empty?
        print_h2 "Process Events", options
        print_process_events(process['events'], options)
      end
    else
      print reset,"\n"
    end
    return 0, nil
  end

  def print_job_executions(execs, options={})
    if execs.empty?
      print cyan,"No job executions found.",reset,"\n"
    else
      rows = execs.collect do |ex|
        {
            id: ex['id'],
            job: ex['job'] ? ex['job']['name'] : '',
            description: ex['description'] || ex['job'] ? ex['job']['description'] : '',
            type: ex['job'] && ex['job']['type'] ? (ex['job']['type']['code'] == 'morpheus.workflow' ? 'Workflow' : 'Task') : '',
            start: format_local_dt(ex['startDate']),
            duration: ex['duration'] ? format_human_duration(ex['duration'] / 1000.0) : '',
            status: format_job_status(ex['status']),
            error: truncate_string(ex['process'] && (ex['process']['message'] || ex['process']['error']) ? ex['process']['message'] || ex['process']['error'] : '', options[:details] ? nil : 32),
            output: truncate_string(ex['process'] && ex['process']['output'] ? ex['process']['output'] : '', options[:details] ? nil : 32),
        }
      end

      columns = [
          :id, :job, :type, {'START DATE' => :start}, {'ETA/TIME' => :duration}, :status, :error, :output
      ]
      print as_pretty_table(rows, columns, options)
    end
  end

  def format_job_status(status_string, return_color=cyan)
    out = ""
    if status_string
      if ['complete','success', 'successful', 'ok'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      elsif ['error', 'offline', 'failed', 'failure'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{yellow}#{status_string.upcase}"
      end
    end
    out + return_color
  end

  # this is built into CliCommand now...
  # def find_by_name_or_id(type, val)
  #   interface = instance_variable_get "@#{type}s_interface"
  #   typeCamelCase = type.gsub(/(?:^|_)([a-z])/) do $1.upcase end
  #   typeCamelCase = typeCamelCase[0, 1].downcase + typeCamelCase[1..-1]
  #   (val.to_s =~ /\A\d{1,}\Z/) ? interface.get(val.to_i)[typeCamelCase] : interface.list({'name' => val})["#{typeCamelCase}s"].first
  # end

  # refresh execution request until it is finished
  # returns json response data of the last execution request when status reached 'completed' or 'failed'
  def wait_for_job_execution(job_execution_id, options={}, print_output = true)
    refresh_interval = 10
    if options[:refresh_interval].to_i > 0
      refresh_interval = options[:refresh_interval]
    end
    refresh_display_seconds = refresh_interval % 1.0 == 0 ? refresh_interval.to_i : refresh_interval
    unless options[:quiet]
      print cyan, "Refreshing every #{refresh_display_seconds} seconds until execution is complete...", "\n", reset
    end
    job_execution = jobs_interface.get_execution(job_execution_id)['jobExecution']
    while ['new','queued','pending','running'].include?(job_execution['status']) do
      sleep(refresh_interval)
      job_execution = jobs_interface.get_execution(job_execution_id)['jobExecution']
    end
    if print_output && options[:quiet] != true
      print_h1 "Morpheus Job Execution", [], options
      print_job_execution(job_execution, options)
    end
    return job_execution
  end



end
