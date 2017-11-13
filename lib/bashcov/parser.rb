# frozen_string_literal: true

require 'parslet'

module Bashcov
  class Parser < Parslet::Parser
    rule(:keyword) do
      %w[
        if fi else while do done for then return function select continue until
        esac elif in
      ].map { |kw| str(kw) }.reduce(:|).as(:builtin)
    end

    rule(:builtin) do
      %w[
        alias bg bind break builtin caller cd command compgen complete declare
        dirs disown echo enable eval exec exit export false fc fg getopts hash
        help history jobs kill let local logout popd printf pushd pwd read
        readonly set shift shopt source suspend test time times trap true type
        typeset ulimit umask unalias unset wait
      ].map { |kw| str(kw) }.reduce(:|).as(:keyword)
    end

    rule(:space_multiline) { match('\s').repeat(1) }
    rule(:space_oneline) { match('[ \t]').repeat(1) }
    rule(:space_multiline?) { space_multiline.maybe }
    rule(:space_oneline?) { space_oneline.maybe }
    rule(:space) { space_multiline | space_oneline }
    rule(:space?) { space.maybe }

    rule(:linebreak) do
      str("\r") | str("\n") | str("\r\n")
    end

    rule(:short_option) do
      str('-') >> (str('-').absent? >> space.absent?) >> any
    end

    rule(:long_option) do
      str('--') >> (str('-').absent? >> space.absent?) >> any.repeat
    end

    rule(:option_separator) { str('--') }

    # TODO make sure we handle interpolations
    rule(:double_quoted_string) do
      str('"') >> (
        str('\\') >> any |
        str('"').absent? >> any
      ).repeat.as(:double_quoted_string) >> str('"') >> space?
    end

    rule(:single_quoted_string) do
      str("'") >> (
        str("'").absent? >> any
      ).repeat.as(:single_quoted_string) >> str("'") >> space?
    end

    rule(:string) do
      single_quoted_string | double_quoted_string
    end

    rule(:single_quoted_heredoc) do
    end

    # TODO need to handle interpolation here, too
    rule(:double_quoted_heredoc) do
      # TODO dynamic
      str('<<') >> str('-').maybe >> space? >> (space.absent? >> any).repeat.capture(:marker) >> dynamic do |src, ctx|
        (any.repeat(0) >> linebreak).repeat(0) >> str(ctx.captures[:marker]) >> linebreak
      end
    end

    rule(:heredoc) do
      single_quoted_heredoc | double_quoted_heredoc
    end

    rule(:herestring) do
      str('<<<') >> string
    end

    rule(:shell) do
      match('[\s\w]+').repeat
    end

    rule(:process_substitution) do
      str('<(') >> shell >> str(')')
    end

    rule(:subshell_bare) do
      str('(') >> str('(').absent? >> shell >> str(')').absent? >> any >> str(')')
    end

    rule(:subshell_expanded) do
      str('$') >> shell
    end

    rule(:subshell) do
      subshell_bare | subshell_expanded
    end

    rule(:arithmetic_bare) do
      str('((') >> shell.as(:shell) >> str('))')
    end

    rule(:arithmetic_expanded) do
      str('$') >> arithmetic_bare
    end

    rule(:arithmetic) do
      arithmetic_bare | arithmetic_expanded
    end

    rule(:integer) do
      match("[0-9]").repeat(1).as(:integer) >> space?
    end

    root(:shell)
  end
end
