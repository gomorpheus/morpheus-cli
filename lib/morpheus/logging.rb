require 'logger'

# Provides global Logging behavior
# By default, Morpheus::Logging.logger is set to STDOUT with level INFO
#
module Morpheus::Logging

	DEFAULT_LOG_LEVEL = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO  

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

end
