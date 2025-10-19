# frozen_string_literal: true

require "erb"

module SDoc::Helpers
  include ERB::Util

  require_relative "helpers/git"
  include ::SDoc::Helpers::Git

  def method_source_code_and_url(rdoc_method)
    source_code = h(rdoc_method.tokens_to_s) if rdoc_method.token_stream

    if source_code&.match(/File\s(\S+), line (\d+)/)
      source_url = github_url(Regexp.last_match(1), line: Regexp.last_match(2))
      source_code = normalize_indentation(source_code)
    end

    [(source_code unless rdoc_method.instance_of?(RDoc::GhostMethod)), source_url]
  end

  private

  def normalize_indentation(source_code)
    return source_code unless source_code.start_with?('# File')

    source_lines = source_code.lines
    return source_code if source_lines.size < 2

    indent = source_lines.second[/\A */].size
    source_code.gsub(/^ {1,#{indent}}/, '')
  end
end
