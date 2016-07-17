# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Lexer do
  describe ".relevant?" do
    it "expects a string" do
      expect { described_class.relevant?("this") }.not_to raise_error
      expect { described_class.relevant?(123) }.to raise_error(NoMethodError)
    end

    context "given an empty string" do
      it "returns false" do
        expect(described_class.relevant?("")).to be false
      end
    end

    context "given a function declaration without the `function' keyword" do
      it "returns false" do
        expect(described_class.relevant?("my_function()")).to be false
      end
    end

    Bashcov::Lexer::IGNORE_START_WITH.each do |s|
      context "given a string starting with `#{s}'" do
        it "returns false" do
          expect(described_class.relevant?("#{s} and some other stuff")).to be false
        end
      end
    end

    Bashcov::Lexer::IGNORE_END_WITH.each do |s|
      context "given a string ending with `#{s}'" do
        it "returns false" do
          expect(described_class.relevant?("I end with #{s}")).to be false
        end
      end
    end

    Bashcov::Lexer::IGNORE_IS.each do |s|
      context "given a string consisting only of `#{s}'" do
        it "returns false" do
          expect(described_class.relevant?(s)).to be false
        end
      end

      context "given a string containing `#{s}' and other characters" do
        it "returns true" do
          expect(described_class.relevant?("#{s} and some other stuff")).to be true
        end
      end
    end
  end
end
