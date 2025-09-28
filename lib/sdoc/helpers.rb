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
    end

    [rdoc_method.instance_of?(RDoc::GhostMethod) ? nil : source_code, source_url]
  end
end
