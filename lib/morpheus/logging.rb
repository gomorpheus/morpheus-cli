require 'logger'
require 'term/ansicolor'

# Provides global Logging behavior
# By default, Morpheus::Logging.logger is set to STDOUT with level INFO
#
module Morpheus::Logging

  DEFAULT_LOG_LEVEL = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO

  AUTHORIZATION_HEADER = 'Authorization'
  SECRET_TOKEN_HEADERS = ['X-Morpheus-Token', 'X-Cypher-Token', 'X-Vault-Token', 'X-Morpheus-Lease']

  @@log_level = DEFAULT_LOG_LEVEL
  @@logger = nil

  # Morpheus::Logging::Logger looks just like a typical Logger
  class Logger < ::Logger
  end

  # Mixin for any class that need a logger instance
  module HasLogger

    def logger
      @logger ||= Morpheus::Logging.logger
    end

  end


  # global methods


  # get the global logger instance
  def self.logger
    if !@@logger
      set_logger(STDOUT, @@log_level)
    end
    @@logger
  end

  # set the global logger to another logger or filename
  def self.set_logger(logdev, log_level = @@log_level)
    @@logger = logdev.is_a?(Logger) ? logdev : Logger.new(logdev)
    @@logger.level = log_level || DEFAULT_LOG_LEVEL
    @@logger.formatter = proc do |severity, datetime, progname, msg|
      "#{msg}\n"
    end
    @@logger
  end

  # set the global log level
  def self.log_level
    @@log_level
  end

  # set the global log level
  def self.set_log_level(level)
    @@log_level = level.to_i
    if @@logger
      @@logger.level = @@log_level
    end
    @@log_level
  end

  # alias for set_log_level(level)
  # def self.log_level=(level)
  #   self.set_log_level(level)
  # end

  # is log level debug?
  def self.debug?
    # self.log_level && self.log_level <= Logger::DEBUG
    self.logger.debug?
  end

  # whether or not to print stack traces
  def self.print_stacktrace?
    self.debug?
  end

  # mask well known secrets and password patterns
  def self.scrub_message(msg)
    if msg.is_a?(String)
      msg = msg.clone
      # looks for RestClient format (hash.inspect) and request/curl output name: value
      msg.gsub!(/Authorization\"\s?\=\>\s?\"Bearer [^"]+/i, 'Authorization"=>"Bearer ************')
      msg.gsub!(/Authorization\:\s?Bearer [^"'']+/i, 'Authorization: Bearer ************')
      # msg.gsub!(/#{AUTHORIZATION_HEADER}\"\s?\=\>\s?\"Bearer [^"]+/, "#{AUTHORIZATION_HEADER}"=>"Bearer ************")
      # msg.gsub!(/#{AUTHORIZATION_HEADER}\:\s?Bearer [^"'']+/, "#{AUTHORIZATION_HEADER}: Bearer ************")
      SECRET_TOKEN_HEADERS.each do |header|
        msg.gsub!(/#{header}\"\s?\=\>\s?\"[^"]+/, "#{header}\"=>\"************")
        msg.gsub!(/#{header}\:\s?[^"'']+/, "#{header}: ************")
      end
      msg.gsub!(/password\"\s?\=\>\s?\"[^"]+/i, 'password"=>"************')
      msg.gsub!(/password\=\"[^"]+/i, 'password="************')
      msg.gsub!(/password\=[^"'&\Z]+/i, 'password=************') # buggy, wont work with ampersand or quotes in passwords! heh
      msg.gsub!(/passwordConfirmation\=[^" ]+/i, 'passwordConfirmation="************')
      msg.gsub!(/passwordConfirmation\=[^" ]+/i, 'passwordConfirmation=************')
    end
    msg
  end

  # An IO class for printing debugging info
  # This is used as a proxy for ::RestClient.log printing right now.
  class DarkPrinter
    include Term::ANSIColor

    # [IO] to write to
    attr_accessor :io

    # [String] ansi color code for output. Default is dark
    attr_accessor :color

    # DarkPrinter with io STDOUT
    def self.instance
      @instance ||= self.new(STDOUT, nil, true)
    end

    def self.print(*messages)
      instance.print(*messages)
    end

    def self.puts(*messages)
      instance.puts(*messages)
    end

    def self.<<(*messages)
      instance.<<(*messages)
    end

    def initialize(io, color=nil, is_dark=true)
      @io = io # || $stdout
      @color = color # || cyan
      @is_dark = is_dark
    end

    def scrub_message(msg)
      Morpheus::Logging.scrub_message(msg)
    end

    def print_with_color(&block)
      if Term::ANSIColor.coloring?
        @io.print Term::ANSIColor.reset
        @io.print @color if @color
        @io.print Term::ANSIColor.dark if @is_dark
      end
      yield
      if Term::ANSIColor.coloring?
        @io.print Term::ANSIColor.reset
      end
    end

    def print(*messages)
      if @io
        messages = messages.flatten.collect {|it| scrub_message(it) }
        print_with_color do 
          messages.each do |msg|
            @io.print msg
          end
        end
      end
    end

    def puts(*messages)
      if @io
        messages = messages.flatten.collect {|it| scrub_message(it) }
        print_with_color do 
          messages.each do |msg|
            @io.puts msg
          end
        end
      end
    end

    def <<(*messages)
      print(*messages)
    end

  end

end
