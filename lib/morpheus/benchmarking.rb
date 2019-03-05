require 'securerandom'
require 'morpheus/logging'
require 'morpheus/cli/cli_registry.rb'

# Provides global Benchmarking functionality
# This provides a store of benchmarking records which can be looked up by name.
# There is also a global enabled flag that can be used.
# There is a mixin HasBenchmarking which provides start_benchmark(), stop_benchmark() and with_benchmark()
#
module Morpheus::Benchmarking

  # a global toggle switch for benchmarking
  @@enabled = false

  def self.enabled?
    @@enabled  
  end
  
  def self.enabled
    @@enabled
  end

  def self.enabled=(val)
    @@enabled = !!val
  end

  # internal Array to store benchmark records for recording
  # todo: garbage cleanup, roll these off to disk probably.
  @@benchmark_record_list = []
  def self.benchmark_record_list
    @@benchmark_record_list
  end

  # internal Hash to lookup benchmark records by id
  @@benchmark_id_store = {}
  def self.benchmark_id_store
    @@benchmark_id_store
  end
  
  # internal Hash to lookup benchmark records by name
  @@benchmark_name_store = {}
  def self.benchmark_name_store
    @@benchmark_name_store
  end

  # start a new BenchmarkRecord
  # @params opts [String or Hash] String as name like like "my routine" or with a Hash like {name: "my routine"}
  #         Just a String for name is fine because there are no other settings of interest at the moment.
  #         Optional, a test can be created without a name. A random :id will be available in the response.
  # Examples:
  #   Morpheus::Benchmarking.start()
  #   Morpheus::Benchmarking.start("my routine")
  # @returns BenchmarkRecord that looks like  {id: ID, name:"my routine",start_time:Time}
  def self.start(opts={})
    benchmark_record = BenchmarkRecord.new(opts)
    benchmark_record_list << benchmark_record
    # index name and id
    if benchmark_record.name
      benchmark_name_store[benchmark_record.name.to_s] = benchmark_record
    end
    if benchmark_record.id
      benchmark_id_store[benchmark_record.id.to_s] = benchmark_record
    end
    #benchmark_record.start() # initialize does it 
    return benchmark_record
  end

  # stop a BenchmarkRecord identified by name or options
  # maybe: if opts is nil, the last record is returned
  # @params opts [String or Hash] String as name like like "my routine" or with a Hash like {name: "my routine"} or {id:ID}
  # @returns BenchmarkRecord that looks like {id: ID, name:"my routine",start_time:Time}
  def self.stop(opts, exit_code=0, error=nil)
    benchmark_record = self.lookup(opts)
    if benchmark_record
      benchmark_record.stop(exit_code, error)
      return benchmark_record
    else
      return nil
    end
  end

  # lookup a BenchmarkRecord identified by name or options, usually just name.
  # @params cmd [String or Hash] Name like "my routine" or with a Hash like {id: ID}
  # @returns BenchmarkRecord that looks like  {id: ID, name:"my routine",start_time:Time}
  def self.lookup(opts={})
    benchmark_record = nil
    if opts.nil? || opts.empty?
      benchmark_record = nil
    elsif opts.is_a?(Hash)
      if opts[:id]
        benchmark_record = benchmark_name_store[opts[:id].to_s]
      elsif opts[:name]
        benchmark_record = benchmark_id_store[opts[:name].to_s]
      end
    elsif opts.is_a?(String) || opts.is_a?(Symbol)
      benchmark_record = benchmark_name_store[opts.to_s] || benchmark_id_store[opts.to_s]
    else
      Morpheus::Logging::DarkPrinter.puts "Benchmarking lookup passed a bad lookup argument: #{opts}" if Morpheus::Logging.debug?
    end
    # could to slow traversal of benchmark_record_list here..
    return benchmark_record
  end

  # get last benchmark started. useful if the name, so `benchmark stop` can work
  # use a unique name or else your record may be overwritten!
  def self.last()
    (@@benchmark_record_list || []).last
  end

  # Mixin for any class that needs benchmarking
  module HasBenchmarking

    # true when benchmark is currently running
    # def benchmarking?
    #   !!@benchmark_record
    # end

    # def benchmark_record
    #   @benchmark_record
    # end

    def with_benchmark(opts, &block)
      exit_code, err = 0, nil
      begin
        start_benchmark(opts)
        if block_given?
          result = block.call()
          exit_code, err = Morpheus::Cli::CliRegistry.parse_command_result(result)
        end
      rescue => ex
        raise ex
        exit_code = 1
        err = ex.msg
      ensure
        stop_benchmark(exit_code, err)
      end
      #return result
      return exit_code, err
    end

    def start_benchmark(opts)
      @benchmark_record = BenchmarkRecord.new(opts)
      return @benchmark_record
    end

    # finish the current benchmark and optionally print the time taken.
    def stop_benchmark(exit_code=0, err=nil)
      if @benchmark_record
        @benchmark_record.stop(exit_code, err)
        @last_benchmark_record = @benchmark_record
        @benchmark_record = nil
        return @last_benchmark_record
      else
        return nil
      end
    end

  end

  # An internal class for modeling benchmark info on a single run.
  # Examples:
  #   BenchmarkRecord.new()
  #   BenchmarkRecord.new("my routine")
  #   BenchmarkRecord.new({name:"my routine"})
  class BenchmarkRecord
    
    attr_reader :id, :name, :command, :start_time, :end_time, :exit_code, :error
  
    def initialize(opts={})
      # no info is fine, anonymous benchmark is cool
      if opts.nil? || opts.empty?
        opts = {}
      end
      # support String
      opts = opts.is_a?(Hash) ? opts : {name: opts.to_s}
      @id = opts[:id] || self.object_id
      @name = opts[:name]
      #@command = opts[:command]
      # store the list of commands would be cool... to record adhoc scripts
      # @commands = []
      # @commands << @command if @command
      start()
    end

    def start()
      if !@start_time
        @start_time = Time.now
      end
      return self
    end

    def stop(exit_code=0, error=nil)
      if !@end_time
        @end_time = Time.now
        @exit_code = exit_code
        @error = error
      end
      return self
    end

    def duration
      if @start_time && @end_time
        return @end_time - @start_time
      elsif @start_time
        return Time.now - @start_time
      else
        return 0
      end
    end

    def msg
      time_str = ""
      seconds = self.duration
      if seconds > 0.002
        seconds = seconds.round(3)
      else
        #seconds = seconds.round(3)
      end
      duration_str = duration
      if @start_time && @end_time
        time_str = "#{seconds} seconds"
      elsif @start_time
        time_str = "#{seconds} seconds (running)"
      else
        time_str = "(unstarted)"
      end
      command_str = "#{@name}" # or "#{@name || @id}"
      exit_str = "#{@exit_code}"
      error_str = "#{@error}" # should inspect and format this
      out = ""
      
      if @end_time
        out << "#{command_str.ljust(30, ' ')}"
      else
        out << "#{command_str.ljust(30, ' ')}"
      end

      # if @end_time
      #   out << "finished: #{command_str.ljust(30, ' ')}"
      # else
      #   out << "running: #{command_str.ljust(30, ' ')}"
      # end
      
      #out = "benchmark: #{command_str.ljust(22, ' ')}   time: #{time_str.ljust(9, ' ')}   exit: #{exit_str.ljust(2, ' ')}"
      # out = "benchmark: #{command_str.ljust(27, ' ')}   time: #{time_str.ljust(9, ' ')}   exit: #{exit_str.ljust(2, ' ')}"
      #out = "time: #{time_str.ljust(9, ' ')}   exit: #{exit_str.ljust(2, ' ')}   exec: #{command_str}"
      # how about a command you can copy and paste?
      # out = "time: #{time_str.ljust(9, ' ')}   exit: #{exit_str.ljust(2, ' ')}   #{command_str}"
      # out = "time: #{time_str.ljust(9, ' ')}   exit: #{exit_str.ljust(4, ' ')}   benchmark exec '#{command_str}'"
      if @end_time || @exit_code
        out << "\texit: #{exit_str.ljust(2, ' ')}"
      end
      if @end_time && @exit_code != 0 && @error
        out << "\terror: #{error_str.ljust(12, ' ')}"
      end

      out << "\t#{time_str.ljust(9, ' ')}"
      

      return out
    end

    def to_s
      msg
    end

  end

end
