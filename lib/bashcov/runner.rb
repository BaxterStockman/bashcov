# frozen_string_literal: true

require "bashcov/errors"
require "bashcov/field_stream"
require "bashcov/lexer"
require "bashcov/xtrace"

module Bashcov
  # Runs a given command with xtrace enabled then computes code coverage.
  class Runner
    attr_reader :files

    # @param [String] command Command to run
    def initialize(command)
      @command = command
      @files = {}
    end

    # Runs the command with appropriate xtrace settings.
    # @note Binds Bashcov +stdin+ to the program being executed.
    # @return [Process::Status] Status of the executed command
    def run
      # Clear out previous run
      @result = nil

      field_stream = FieldStream.new
      @xtrace = Xtrace.new(field_stream)

      fd = @xtrace.file_descriptor
      env = { "PS4" => Xtrace.ps4 }
      options = { in: :in }

      if Bashcov.options.mute
        options[:out] = "/dev/null"
        options[:err] = "/dev/null"
      end

      run_xtrace(fd, env, options) do
        command_pid = Process.spawn env, *@command, options # spawn the command

        begin
          # start processing the xtrace output
          xtrace_thread = Thread.new { @xtrace.read }

          Process.wait command_pid

          @xtrace.close

          @files = xtrace_thread.value # wait for the thread to return
        rescue XtraceError => e
          write_warning <<-WARNING
            encountered an error parsing Bash's output (error was:
            #{e.message}). This can occur if your script or its path contains
            the sequence #{Xtrace.delimiter.inspect}, or if your script unsets
            LINENO. Aborting early; coverage report will be incomplete.
          WARNING

          @files = e.files
        end
      end

      $?
    end

    # @return [Hash] Coverage hash of the last run
    # @note The result is memoized.
    def result
      @result ||= begin
        find_bash_files!
        expunge_invalid_files!
        convert_coverage
      end
    end

  private

    def write_warning(message)
      warn format "%s: warning: %s", Bashcov.program_name,
                  message.gsub(/^\s+/, "").lines.map(&:chomp).join(" ")
    end

    def run_xtrace(fd, env, options)
      # Older versions of Bash (< 4.1) don't have the BASH_XTRACEFD variable
      if Bashcov.bash_xtracefd?
        options[fd] = fd # bind FDs to the child process

        env["BASH_XTRACEFD"] = fd.to_s
      else
        # Send subprocess standard error to @xtrace.file_descriptor
        options[:err] = fd

        # Don't bother issuing warning if we're silencing output anyway
        unless Bashcov.mute
          write_warning <<-WARNING
            you are using a version of Bash that does not support
            BASH_XTRACEFD. All xtrace output will print to standard error, and
            your script's output on standard error will not be printed to the
            console.
          WARNING
        end
      end

      inject_env! do
        yield
      end
    end

    # @note +SHELLOPTS+ must be exported so we use Ruby's {ENV} variable
    # @yield [void] adds "xtrace" to +SHELLOPTS+ and then runs the provided
    #   block
    # @return [Object, ...] the value returned by the calling block
    def inject_env!
      existing_flags_s = ENV["SHELLOPTS"]
      existing_bash_env = ENV["BASH_ENV"]

      existing_flags = (existing_flags_s || "").split(":")

      ENV["SHELLOPTS"] = (existing_flags | ["xtrace"]).join(":")
      #ENV["BASH_ENV"] = "/home/matt/git/bashcov/ext/wraptrap.sh"
      yield
    ensure
      ENV["SHELLOPTS"] = existing_flags_s
      ENV["BASH_ENV"] = existing_bash_env
    end

    # Add files which have not been executed at all (i.e. with no coverage)
    # @return [void]
    def find_bash_files!
      return if Bashcov.skip_uncovered

      Pathname.glob("#{Bashcov.root_directory}/**/*.sh").each do |filename|
        files[filename] = Bashcov::SourceFile.new(filename) unless files.include?(filename)
      end
    end

    # @return [void]
    def expunge_invalid_files!
      files.delete_if do |filename, *|
        unless filename.file?
          write_warning <<-WARNING
            #{filename} was executed but has been deleted since then - it won't
            be reported in coverage.
          WARNING

          true
        end
      end
    end

    def convert_coverage
      coverage_pairs = files.map do |filename, source_file|
        source_file.lex!(Lexer)
        source_file.filter!(*Bashcov.filters)
        [filename.to_s, source_file.to_coverage]
      end

      Hash[coverage_pairs]
    end
  end
end
