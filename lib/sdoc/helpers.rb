# frozen_string_literal: true

require "erb"

module SDoc::Helpers
  include ERB::Util

  require_relative "helpers/git"
  include ::SDoc::Helpers::Git

  def description_for(rdoc_object)
    if rdoc_object.comment && !rdoc_object.comment.empty?
      %(<div class="description">#{rdoc_object.description}</div>)
    end
  end

  def method_signature(rdoc_method)
    signature = if rdoc_method.call_seq
      # Support specifying a call-seq like `to_s -> string`
      rdoc_method.call_seq.gsub(/^\s*([^(\s]+)(.*?)(?: -> (.+))?$/) do
        "<b>#{h $1}</b>#{h $2}#{" <span class=\"returns\">&rarr;</span> #{h $3}" if $3}"
      end
    else
      "<b>#{h rdoc_method.name}</b>#{h rdoc_method.params}"
    end

    "<code>#{signature}</code>"
  end

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
