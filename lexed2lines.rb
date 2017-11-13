#!/usr/bin/env ruby

require 'rouge'
require 'pathname'

def lexed2lines(r)
  return enum_for(__method__, r) unless block_given?
  lineno = 1
  r.each do |tok, text|
    yield [tok, text, lineno]
    lineno += text.scan(/(?:\r|\n|\r\n)/).length
  end
end

def lexed2relevant(r)
  return enum_for(__method__, r) unless block_given?
  lexed2lines(r).each do |tok, text, lineno|
    yield [tok, text, lineno, tok.name]
  end
end

def lex_with_states(lexer, string)
  return enum_for(__method__, lexer, string) unless block_given?
  lexer.lex(string) do |token, text|
    yield [lexer.state, token, text]
  end
end

def group_by_tokens(r)

end

if caller.empty?
  f = Pathname.getwd.join(ARGV[0])
  l = Rouge::Lexer.guess(source: f.read, filename: f.to_s)
  r = l.lex(f.read)
  require 'yaml'
  puts lexed2relevant(r).to_a.inspect
end
