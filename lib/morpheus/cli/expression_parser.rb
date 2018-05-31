require 'shellwords'

# Provides parsing of user input into an Array of expressions for execution
# Syntax currently supports the && and || operators, and the use of parenthesis
# returns an Array of objects.
# Each object might be a command (String), an operator (well known String) 
# or another expression (Array)
module Morpheus::Cli::ExpressionParser

  # An error class for invalid expressions
  class InvalidExpression < StandardError
  end

  ## constants used internally for parsing morpheus expressions
  # note: the space padding in the _TOKEN strings is important for splitting

  OPEN_PARENTHESIS = "("
  OPEN_PARENTHESIS_TOKEN = "___+++OPEN_PARENTHESIS+++___"
  OPEN_PARENTHESIS_REGEX = /(\()(?=(?:[^"']|"[^'"]*")*$)/

  CLOSED_PARENTHESIS = ")"
  CLOSED_PARENTHESIS_TOKEN = "___+++CLOSED_PARENTHESIS+++___"
  CLOSED_PARENTHESIS_REGEX = /(\))(?=(?:[^"']|"[^'"]*")*$)/

  AND_OPERATOR = "&&"
  AND_OPERATOR_TOKEN = "___+++AND_OPERATOR+++___"
  AND_OPERATOR_REGEX = /(\&\&)(?=(?:[^"']|"[^'"]*")*$)/

  OR_OPERATOR = "||"
  OR_OPERATOR_TOKEN = "___+++OR_OPERATOR+++___"
  OR_OPERATOR_REGEX = /(\|\|)(?=(?:[^"']|"[^'"]*")*$)/

  PIPE_OPERATOR = "|"
  PIPE_OPERATOR_TOKEN = "___+++PIPE_OPERATOR+++___"
  PIPE_OPERATOR_REGEX = /(\|)(?=(?:[^"']|"[^'"]*")*$)/

  COMMAND_DELIMETER = ";"
  COMMAND_DELIMETER_REGEX = /(\;)(?=(?:[^"']|"[^'"]*")*$)/
  COMMAND_DELIMETER_TOKEN = "___+++COMMAND_DELIMETER+++___"

  # parse an expression of morpheus commands into a list of expressions
  def self.parse(input)
    result = []
    # first, build up a temporary command string
    # swap in well known tokens so we can split it safely
    expression_str = input.dup.to_s
    expression_str.gsub!(OPEN_PARENTHESIS_REGEX, " #{OPEN_PARENTHESIS_TOKEN} ")
    expression_str.gsub!(CLOSED_PARENTHESIS_REGEX, " #{CLOSED_PARENTHESIS_TOKEN} ")
    expression_str.gsub!(AND_OPERATOR_REGEX, " #{AND_OPERATOR_TOKEN} ")
    expression_str.gsub!(OR_OPERATOR_REGEX, " #{OR_OPERATOR_TOKEN} ")
    expression_str.gsub!(PIPE_OPERATOR_REGEX, " #{PIPE_OPERATOR_TOKEN} ")
    expression_str.gsub!(COMMAND_DELIMETER_REGEX, " #{COMMAND_DELIMETER_TOKEN} ")
    # split on unquoted whitespace
    tokens = expression_str.split(/(\s)(?=(?:[^"']|"[^'"]*")*$)/).collect {|it| it.to_s.strip }.select {|it| !it.empty?  }.compact
    # swap back for nice looking tokens
    tokens = tokens.map do |t|
      case t
      when OPEN_PARENTHESIS_TOKEN then OPEN_PARENTHESIS
      when CLOSED_PARENTHESIS_TOKEN then CLOSED_PARENTHESIS
      when AND_OPERATOR_TOKEN then AND_OPERATOR
      when OR_OPERATOR_TOKEN then OR_OPERATOR
      when PIPE_OPERATOR_TOKEN then PIPE_OPERATOR
      when COMMAND_DELIMETER_TOKEN then COMMAND_DELIMETER
      else
        t
      end
    end
    
    # result = parse_expression_from_tokens(tokens)
    begin
      result = parse_expression_from_tokens(tokens)
    rescue InvalidExpression => ex
      raise InvalidExpression.new("#{ex}. Invalid Expression: #{input}")
    end
    return result
  end

  # turn a flat list of tokens into an array of expressions
  def self.parse_expression_from_tokens(tokens)
    result = []
    remaining_tokens = tokens.dup
    current_command_tokens = []
    while !remaining_tokens.empty?
      token = remaining_tokens.shift
      if token == CLOSED_PARENTHESIS
        raise InvalidExpression.new("Encountered a closed parenthesis ')' with no matching open parenthesis '('")
      elsif token == OPEN_PARENTHESIS
        # add the command
        if current_command_tokens.size != 0
          result << current_command_tokens.join(" ")
          current_command_tokens = []
        end
        # start of a new sub expression
        # find the index of the matching closed parenthesis
        cur_expression_index = 0
        closed_parenthesis_index = nil
        remaining_tokens.each_with_index do |t, index|
          if t == OPEN_PARENTHESIS
            cur_expression_index += 1
          elsif t == CLOSED_PARENTHESIS
            if cur_expression_index == 0
              closed_parenthesis_index = index
              break
            else
              cur_expression_index -= 1
            end
          end
          if cur_expression_index < 0
            raise InvalidExpression.new("Encountered a closed parenthesis ')' with no matching open parenthesis '('")
          end
        end
        if !closed_parenthesis_index
          raise InvalidExpression.new("Encountered an open parenthesis '(' with no matching closed parenthesis ')'")
        end
        # ok, parse a subexpression for the tokens up that index
        sub_tokens = remaining_tokens[0..closed_parenthesis_index-1]
        result << parse_expression_from_tokens(sub_tokens)
        # continue on parsing the remaining tokens
        remaining_tokens = remaining_tokens[closed_parenthesis_index + 1..remaining_tokens.size - 1]
      elsif token == AND_OPERATOR || token == OR_OPERATOR || token == PIPE_OPERATOR
        # add the command
        if current_command_tokens.size != 0
          result << current_command_tokens.join(" ")
          current_command_tokens = []
        end
        # add the operator
        result << token
      elsif token == COMMAND_DELIMETER
        # add the command
        if current_command_tokens.size != 0
          result << current_command_tokens.join(" ")
          current_command_tokens = []
        end
      else
        # everything else is assumed to be part of a command, inject it
        current_command_tokens << token
      end
    end
    
    # add the command
    if current_command_tokens.size != 0
      result << current_command_tokens.join(" ")
      current_command_tokens = []
    end

    return result
  end

end
