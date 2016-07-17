# frozen_string_literal: true

require "simplecov/source_file"

module Bashcov
  # {SourceFile} represents a Bash script.
  class SourceFile
    # {Command} represents a chunk of code.
    class Command < SimpleCov::SourceFile::Line
      # Uncovered line
      # @see http://ruby-doc.org/stdlib-2.3.0/libdoc/coverage/rdoc/Coverage.html
      UNCOVERED = 0

      # Ignored line
      # @see http://ruby-doc.org/stdlib-2.3.0/libdoc/coverage/rdoc/Coverage.html
      IGNORED = nil

      # @!attribute [r] src
      #   @return [String] The source code of the command

      # @!attribute [r] line_number
      #   @return [Integer] The line number upon which the command appears

      # @!attribute [r] coverage
      #   @return [Integer, nil] The number of times the {Command} has been
      #     executed, or +nil+ if it has not been executed

      # Increment the coverage count for this command
      # @param [Int] n  the amount by which to increment the coverage count
      # @return [Int]   the total number of times the command has been executed
      #   so far
      def increment(n = 1)
        @coverage = @coverage.nil? ? n : @coverage + n
      end

      # Mark command as uncovered
      # @return [UNCOVERED]
      def uncovered!
        @coverage = UNCOVERED
      end

      # Mark command as ignored
      # @return [IGNORED]
      def ignored!
        @coverage = IGNORED
      end

      # Whether the {Command} object represents a blank or unexecuted line
      # @return [Boolean] +true+ if the command is a blank line or has not been
      #   executed, +false+ otherwise
      def empty?
        src.empty?
      end

      def copy_coverage!(other)
        @coverage = other.coverage
      end

      # Whether two {Command} objects are equivalent
      # @param  [Command] other a {Command} object
      # @return [Boolean] whether the two {Command}s are equivalent.
      #   {Command}s are considered equivalent when their {#src} and
      #   {#line_number} attributes both return +true+ for +#eql?+
      def eql?(other)
        src == other.src && line_number == other.line_number
      end
      alias == eql?
    end

    # @!attribute [r] lines
    #   An array of +Hashes+.  Each index in the array represents a line
    #   number, and the values of the +Hash+es located at that index are
    #   {Command} objects representing the commands appearing on that line,
    #   keyed to their respective {Command#src} attributes.
    #   @return [Array<Hash{String => Array<Command>}>]
    # @!attribute [r] filename
    #   @return [String, Pathname]  the name of the Bash script
    attr_reader :lines, :filename

    # Create an instance of {SourceFile}.
    # @param [String, Pathname] filename  the name of the Bash script
    def initialize(filename)
      @filename = filename
      @lines = []
    end

    # Merge a {Command} object into existing coverage
    # @param [Command]  cmd a {Command} object
    # @return [Command] a {Command} representing the +cmd+ parameter's chunk of
    #   source code, with {Command#coverage} incremented appropriately
    def merge_command!(cmd)
      lines[cmd.line_number] ||= {}

      # Increment the coverage for matching commands
      if lines[cmd.line_number].key?(cmd.src)
        lines[cmd.line_number][cmd.src].increment(cmd.coverage)
      # Otherwise, insert the new command
      else
        lines[cmd.line_number][cmd.src] = cmd
      end

      lines[cmd.line_number][cmd.src]
    end
    alias << merge_command!

    # Set or increment coverage for a chunk of source code
    # @see Command#initialize
    def add_command(src, line_number, coverage)
      merge_command!(Command.new(src, line_number, coverage))
    end

    # Open {#filename} for reading.
    def open(*ary, &block)
      File.open(filename, *ary, &block)
    end

    # Remove commands whose {Command#src} matches any of a list of +Regexp+s.
    def filter!(*filters)
      lines.each do |line_hash|
        next if line_hash.nil?

        line_hash.each_key do |src|
          filters.each do |f|
            if f =~ src
              puts "#=> `#{src}' matches `#{f.source}'"
            end
          end
        end

        line_hash.delete_if do |src, _|
          filters.any? { |f| f =~ src }
        end
      end

      self
    end

    # Mark unexecuted commands as uncovered.
    # @see Lexer
    # @param [#relevant?] lexer An object exposing the +#relevant?+ method,
    #   which should take a +String+ representing a line from a Bash file as
    #   the sole argument and return +true+ if the line contains a valid Bash
    #   command and +false+ otherwise
    # @return [void]
    def lex!(lexer)
      open do |file|

        continuation_line = false
        file.each_line do |line|
          # @see +SimpleCov::SourceFile::Command+
          # .never? => not skipped and +nil+ for coverage
          if lexer.relevant?(line)
            add_command(line, file.lineno, Command::IGNORED) if lines[file.lineno].nil?

            if continuation_line
              lines[file.lineno].values.take_while(&:never?).map(&:ignored!)
            elsif (cmds = lines[file.lineno].values).count(&:never?) == cmds.length
              cmds.each(&:uncovered!)
            end
          else
            lines[file.lineno] = {}
          end

          # Line ends with '\', meaning that the next non-comment,
          # non-whitespace line is a continuation of this command.
          continuation_line = line.chomp.end_with?("\\")
        end
      end

      self
    end

    # Iterate over the lines comprising the Bash script.
    # @return [Enumerator]  an +Enumerator+ that yields, in order of line
    #   number, an +Array+ of {Command}s
    # @yieldparam [Array<Command>]  line  an array of {Command}s comprising the
    #   current line
    def each
      return enum_for(__method__) unless block_given?
      #lines[1..-1].map { |l| l.nil? ? [] : l.values }.each(&Proc.new)
      self[1..-1].each(&Proc.new)
    end

    # @return [Hash{Integer => Array<Command>}] A +Hash+ mapping line numbers
    #   to +Array+s of the {Command}s appearing on that line
    def to_h
      Hash[each.each_with_index.map { |l, i| [i + 1, l] }]
    end

    # @return [Array<Integer>]  An +Array+ in which indices represent line
    #   numbers and entries represent the total coverage for that line
    # @example
    #   sf = Bashcov::SourceFile.new("script.sh")
    #
    #   # Much later...
    #   SimpleCov::Result.new({sf.filename => sf.to_coverage})
    def to_coverage
      each.map { |l| l.empty? ? Command::IGNORED : l.compact.map(&:coverage).reduce(:+) }
    end

    # @return [Hash{Integer => Array<String>}] A has similar to the one
    #   returned by {#to_h}, but in which the values are instead an +Array+ of
    #   +String+s representing the {Command#src} attribute of each command in
    #   the line
    def dump
      Hash[to_h.map { |i, l| [i, l.empty? ? Command::IGNORED : l.map(&:src)] }]
    end

    # Access a line in the {SourceFile} by line number.
    # @param  [Integer, Range<Integer>] i The +i+th line in the file, or a
    #   +Range+ referring to a range of line indices
    # @return [Array<Command>]  The set of {Command}s comprising the +i+th line
    # @note +sf[0]+ will always be +nil+.
    def slice(*ary)
      case (slice = lines[*ary])
      when Array
        slice.map { |l| l.nil? ? [] : l.values }
      else
        slice.nil? ? [] : slice.values
      end
    end
    alias [] slice
  end
end
