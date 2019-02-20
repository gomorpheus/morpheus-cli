require 'morpheus/logging'
require 'morpheus/benchmarking'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::BenchmarkCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'benchmark'

  # control global benchmark toggle
  register_subcommands :on, :off, :on?, :off?
  # record your own benchmarks
  register_subcommands :start, :stop, :status, :exec => :execute


  # this would be cool, we should store all benchmarking results in memory or on disk =o
  # register_subcommands :list, :get, :put, :remove

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    # no connection needed
  end

  def handle(args)
    handle_subcommand(args)
  end

  def on(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Enable global benchmarking. 
This behaves the same as if you were to add the -B switch to every command.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    Morpheus::Benchmarking.enabled = true
    my_terminal.benchmarking = Morpheus::Benchmarking.enabled
    puts "#{cyan}benchmark: #{green}on#{reset}" unless options[:quiet]
    return 0 
  end

  def off(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Disable global benchmarking. 
The default state for this setting is off.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    Morpheus::Benchmarking.enabled = false
    my_terminal.benchmarking = Morpheus::Benchmarking.enabled
    puts "#{cyan}benchmark: #{dark}off#{reset}" unless options[:quiet]
    return 0 
  end

  def on?(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Print the value of the global benchmark setting. 
Exit 0 if on.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    if Morpheus::Benchmarking.enabled?
      puts "#{cyan}benchmark: #{green}on#{reset}" unless options[:quiet]
    else
      puts "#{cyan}benchmark: #{dark}off#{reset}" unless options[:quiet]
    end
    return Morpheus::Benchmarking.enabled? ? 0 : 1
  end

  def off?(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Print the value of the global benchmark setting. 
Exit 0 if off.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    unless options[:quiet]
      if Morpheus::Benchmarking.enabled?
        puts "#{cyan}benchmark: #{green}on#{reset}"
      else
        puts "#{cyan}benchmark: #{dark}off#{reset}"
      end
    end
    return Morpheus::Benchmarking.enabled? ? 1 : 0
  end

  def start(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Start recording a benchmark.
[name] is required. This is just a name for the routine.
This allows you to record how long it takes to run a series of commands.
Just run `benchmark stop` when you are finished.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # if args.count < 1
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
    #   return 1
    # end
    benchmark_name = nil
    if !args.empty?
      benchmark_name = args.join(' ')
    end
    benchmark_record = Morpheus::Benchmarking.start(benchmark_name)
    unless options[:quiet]
      if benchmark_record.name
        print_green_success "Started benchmark '#{benchmark_record.name}'"
      else
        print_green_success "Started benchmark"
      end
    end
    # record this record so it can be stopped later without knowing (or remembering) the name

    return 0 
  end

  def stop(args)
    options = {}
    params = {}
    benchmark_exit_code = nil
    benchmark_err = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--exit CODE', String, "Exit code to end benchmark with. Default is 0 to indicate success.") do |val| # default should my_terminal.last_exit_code
        benchmark_exit_code = val.to_i
      end
      opts.on('--error ERROR', String, "Error message to include with a benchmark that failed.") do |val|
        benchmark_err = val
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Stop recording a benchmark.
[name] is optional. This is the name of the benchmark to stop. 
The last benchmark is used by default.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # if args.count < 1
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
    #   return 1
    # end
    # benchmark_name = args.join(' ')
    # benchmark_record = Morpheus::Benchmarking.stop(benchmark_name)

    benchmark_name = nil
    benchmark_record = nil
    if args.empty?
      # stop the last one..
      benchmark_record = Morpheus::Benchmarking.last
      if benchmark_record.nil?
        print_error red,"Benchmark not found",reset,"\n"
        return 1
      end
    else
      benchmark_name = args.join(' ')
      benchmark_record = Morpheus::Benchmarking.lookup(benchmark_name)
      if benchmark_record.nil?
        print_error red,"Benchmark not found by name '#{benchmark_name}'",reset,"\n"
        return 1
      end
    end
    if benchmark_record.start_time == nil || benchmark_record.end_time != nil
      if benchmark_record.name
        print_error red,"Benchmark '#{benchmark_record.name}' is not running",reset,"\n"
      else
        print_error red,"Benchmark is not running",reset,"\n"
      end
      return 1
    end
    benchmark_record.stop(benchmark_exit_code || 0, benchmark_err)
    unless options[:quiet]
      if benchmark_record.name
        print_green_success "Stopped benchmark '#{benchmark_record.name}'"
      else
        print_green_success "Stopped benchmark"
      end
    end
    # always print benchmark info
    Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg)
    return 0 
  end

  def status(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Print status of benchmark.
[name] is optional. This is the name of the benchmark to inspect.
The last benchmark is used by default.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # if args.count < 1
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
    #   return 1
    # end
    # benchmark_name = args.join(' ')
    # benchmark_record = Morpheus::Benchmarking.stop(benchmark_name)

    benchmark_name = nil
    benchmark_record = nil
    if args.empty?
      # stop the last one..
      benchmark_record = Morpheus::Benchmarking.last
      if benchmark_record.nil?
        print_error red,"No benchmark is running",reset,"\n"
        return 1
      end
    else
      benchmark_name = args.join(' ')
      benchmark_record = Morpheus::Benchmarking.lookup(benchmark_name)
      if benchmark_record.nil?
        print_error red,"Benchmark not found by name '#{benchmark_name}'",reset,"\n"
        return 1
      end
    end
    
    unless options[:quiet]
      Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg)
    end
    return 0 
  end

  def execute(args)
    benchmark_name = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[command...]")
      opts.on('--name NAME', String, "Name for the benchmark. Default is the command itself.") do |val|
        benchmark_name = val
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Benchmark a specified command.
[command] is required. This is the command to execute
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    
    cmd = args.join(' ')

    #previous_terminal_benchmarking = my_terminal.benchmarking
    start_benchmark(benchmark_name || cmd)
    
    # exit_code, err = my_terminal.execute(cmd)
    # do this way until terminal supports expressions
    cmd_result = execute_commands_as_expression(cmd)
    exit_code, err = parse_command_result(cmd_result)
  
    benchmark_record = stop_benchmark(exit_code, err)
    Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg) if benchmark_record
    
    #my_terminal.benchmarking = previous_terminal_benchmarking
    return 0 
  end

  protected

  # copied these over from shell, consolidate to terminal plz

  def execute_command(cmd)
    my_terminal.execute(cmd)
  end

  def execute_commands_as_expression(input)
    flow = input
    if input.is_a?(String)
      begin
        flow = Morpheus::Cli::ExpressionParser.parse(input)
      rescue Morpheus::Cli::ExpressionParser::InvalidExpression => e
        @history_logger.error "#{e.message}" if @history_logger
        return Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).handle_error(e) # lol
      end
    end
    final_command_result = nil
    if flow.size == 0
      # no input eh?
    else
      last_command_result = nil
      if ['&&','||', '|'].include?(flow.first)
        puts_error "#{Morpheus::Terminal.angry_prompt}invalid command format, begins with an operator: #{input}"
        return 99
      elsif ['&&','||', '|'].include?(flow.last)
        puts_error "#{Morpheus::Terminal.angry_prompt}invalid command format, ends with an operator: #{input}"
        return 99
      # elsif ['&&','||', '|'].include?(flow.last)
      #   puts_error "invalid command format, consecutive operators: #{cmd}"
      else
        #Morpheus::Logging::DarkPrinter.puts "Executing command flow: #{flow.inspect}" if Morpheus::Logging.debug?
        previous_command = nil
        previous_command_result = nil
        current_operator = nil
        still_executing = true
        flow.each do |flow_cmd|
          if still_executing
            if flow_cmd == '&&'
              # AND operator
              current_operator = flow_cmd
              exit_code, cmd_err = parse_command_result(previous_command_result)
              if exit_code != 0
                still_executing = false
              end
            elsif flow_cmd == '||' # or with previous command
              current_operator = flow_cmd
              exit_code, err = parse_command_result(previous_command_result)
              if exit_code == 0
                still_executing = false
              end
            elsif flow_cmd == '|' # or with previous command
              puts_error "The PIPE (|) operator is not yet supported =["
              previous_command_result = nil
              still_executing = false
              # or just continue?
            elsif flow_cmd.is_a?(Array)
              # this is a subexpression, execute it as such
              current_operator = nil
              previous_command_result = execute_commands_as_expression(flow_cmd)
            else # it's a command, not an operator
              current_operator = nil
              previous_command_result = execute_command(flow_cmd)
            end
            previous_command = flow_cmd
          else
            #Morpheus::Logging::DarkPrinter.puts "operator skipped command: #{flow_cmd}" if Morpheus::Logging.debug?
          end
          # previous_command = flow_cmd
        end
        final_command_result = previous_command_result
      end
    end
    return final_command_result
  end

end
