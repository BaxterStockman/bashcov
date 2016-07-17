# frozen_string_literal: true

require "spec_helper"

describe Bashcov::SourceFile do
  let(:cmd_klass) { Bashcov::SourceFile::Command }

  let!(:ignored) { Bashcov::SourceFile::Command::IGNORED }
  let!(:uncovered) { Bashcov::SourceFile::Command::UNCOVERED }

  include_context "temporary script", "dummy_script" do
    let(:script_text) do
      <<-EOF.gsub(/\A\s+/, "")
        #!/bin/bash

        [[ -d /tmp ]] && echo "/tmp exists"

        function meh() {
          :
        }
      EOF
    end

    let(:source_file) { described_class.new(tmpscript.path) }

    let!(:lines) do
      [
        ["#!/bin/bash"],
        [""],
        ["[[ -d /tmp ]]", "echo \"/tmp exists\""],
        [""],
        [":"],
        [""],
      ].each_with_index.map do |cmds, i|
        cmds.map { |cmd| Bashcov::SourceFile::Command.new(cmd, i + 1, ignored) }
      end
    end
  end

  describe Bashcov::SourceFile::Command do
    it "is a subclass of Simplecov::SourceFile::Line" do
      expect(described_class.new("", 1, nil)).to be_a(SimpleCov::SourceFile::Line)
    end

    describe "#src" do
      it "contains the values passed to the constructor" do
        expect(described_class.new("echo this", 1, 0).src).to eq("echo this")
      end
    end

    describe "#increment" do
      context "given no argument" do
        it "increments the coverage count by 1" do
          expect(described_class.new("", 0, uncovered).tap(&:increment).coverage).to eq(1)
        end
      end

      context "given a currently-ignored line" do
        it "assigns the provided number as coverage" do
          expect(described_class.new("", 0, ignored).tap { |c| c.increment(4) }.coverage).to eq(4)
        end
      end

      it "increments the coverage count by the provided number" do
        expect(described_class.new("", 0, 2).tap { |c| c.increment(3) }.coverage).to eq(5)
      end
    end

    describe "#uncovered!" do
      it "marks the command as uncovered" do
        expect(described_class.new("", 0, 3).tap(&:uncovered!).coverage).to be(uncovered)
      end
    end

    describe "#ignored!" do
      it "marks the command as ignored" do
        expect(described_class.new("", 0, 3).tap(&:ignored!).coverage).to be(ignored)
      end
    end

    describe "#empty?" do
      context "given an empty #src" do
        it "returns true" do
          expect(described_class.new("", 0, 3).empty?).to be true
        end
      end

      context "given a non-empty #src" do
        it "returns false" do
          expect(described_class.new("touch /etc", 0, 3).empty?).to be false
        end
      end
    end
  end

  describe "merge_command!" do
    it "adds the command to the appropriate index in the #lines array" do
      cmd = cmd_klass.new("rev <<<'IT_UP'", 10, 1)
      source_file.merge_command!(cmd)

      expect(source_file.lines[10][cmd.src]).to be(cmd)
    end

    context "given a matching command already in the #lines array" do
      it "adds the new command's coverage count" do
        source_file.add_command("rev <<<'IT_UP'", 10, 3)
        cmd = cmd_klass.new("rev <<<'IT_UP'", 10, 1)
        source_file.merge_command!(cmd)

        expect(source_file.lines[10][cmd.src].coverage).to eq(4)
      end
    end
  end

  describe "add_command" do
    it "adds the command to the appropriate index in the #lines array" do
      src = 'md5sum /usr/local/bin/tee'
      n = 23

      source_file.add_command(src, n, uncovered)

      source_file.lines[n][src].tap do |cmd|
        expect(cmd).to be_a(cmd_klass)
        expect(cmd.src).to eq(src)
        expect(cmd.line_number).to eq(n)
      end
    end
  end

  describe "#open" do
    it "opens #filename for reading" do
      source_file.open do |file|
        expect(file.path).to eq(tmpscript.path)
        expect(file.closed?).to be false
      end
    end
  end

  describe "#each" do
    context "given no block" do
      it "returns an enumerator" do
        expect(source_file.each).to be_an(Enumerator)
      end
    end

    context "given a block" do
      before do
        lines.each do |line|
          line.each do |cmd|
            source_file.merge_command!(cmd)
          end
        end
      end

      it "yields the commands in the script ordered by line number" do
        expect { |b| source_file.each(&b) }.to yield_successive_args(*lines)
      end
    end
  end

  describe "#filter!" do
    it "removes commands whose source code matches the provided regexen" do
      source_file.lex!(Bashcov::Lexer)

      expect(source_file[3].map(&:src).first).to match("tmp")

      source_file.filter!(/tmp/)

      expect(source_file[3].map(&:src).first).not_to match("tmp")
    end
  end

  describe "#lex!" do
    before(:each) do
      lines.each do |line|
        line.each do |cmd|
          source_file.merge_command!(cmd)
        end
      end
    end

    it "marks relevant ignored lines as uncovered" do
      source_file.lex!(Bashcov::Lexer)

      expect(source_file[3].map(&:coverage)).to all(eq(uncovered))
    end
  end

  describe "#to_h" do
    let(:to_h) { source_file.to_h }

    it "keys line numbers to lists of commands appearing on that line" do
      source_file.lex!(Bashcov::Lexer)

      to_h.each_pair do |line_number, cmds|
        expect(line_number).to be_an(Integer)
        expect(cmds).to all(be_a(Bashcov::SourceFile::Command))
        expect(cmds.map(&:line_number)).to all(eq(line_number))
      end
    end
  end

  describe "#to_coverage" do
    let(:coverage) { source_file.to_coverage }

    it "creates a coverage array of the form expected by SimpleCov" do
      source_file.lex!(Bashcov::Lexer)

      expect(coverage).to all(be(nil).or((be >= 0)))
    end
  end

  describe "#dump" do
    it "keys line numbers to the source code of commands appearing on that line" do
      source_file.lex!(Bashcov::Lexer)

      source_file.dump.each_pair do |line_number, src_a|
        expect(line_number).to be_an(Integer)
        expect(src_a).to be(nil).or all(be_a(String))
        expect(source_file[line_number].map(&:src)).to contain_exactly(*src_a)
      end
    end
  end

  describe "#[]" do
    it "accesses the commands at the given line number" do
      cmd = cmd_klass.new("rm /", 3, 1)
      source_file.merge_command!(cmd)

      source_file[3].tap do |line|
        expect(line).to be_an(Array)
        expect(line).to include(cmd)
      end
    end
  end
end
