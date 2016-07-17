# frozen_string_literal: true

require "shellwords"

module Bashcov
  # Simple lexer which analyzes Bash files in order to get information for
  # coverage
  module Lexer
    IGNORE_COMMENT = %r/\s*#/

    # Lines starting with one of these tokens are irrelevant for coverage
    IGNORE_START_WITH = %w(# function).freeze

    # Lines ending with one of these tokens are irrelevant for coverage
    IGNORE_END_WITH = %w|(|.freeze

    # Lines containing only one of these keywords are irrelevant for coverage
    IGNORE_IS = %w(esac if then else elif fi while do done { } ;;).freeze

  module_function
    def comment?(l)
      IGNORE_COMMENT =~ l.strip
    end

    def relevant?(l)
      # +l+ is can be frozen
      line = l.strip

      !line.empty? and
        !IGNORE_IS.include? line and
        !line.start_with?(*IGNORE_START_WITH) and
        !line.end_with?(*IGNORE_END_WITH) and
        line !~ /\A\w+\(\)/ # function declared without the 'function' keyword
    end
  end
end
