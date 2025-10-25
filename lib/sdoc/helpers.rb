# frozen_string_literal: true

require "erb"

module SDoc::Helpers
  include ERB::Util

  require_relative "helpers/git"
  include ::SDoc::Helpers::Git

  def link_to(text, url = nil, html_attributes = {})
    url, html_attributes = nil, url if url.is_a?(Hash)
    url ||= text

    text = _link_body(text)

    if url.is_a?(RDoc::CodeObject)
      url = "/#{url.path}"
      default_class = "ref-link" if text.start_with?("<code>") && text.end_with?("</code>")
    end

    html_attributes = html_attributes.transform_keys(&:to_s)
    html_attributes = { "href" => url, "class" => default_class }.compact.merge(html_attributes)

    attribute_string = html_attributes.map { |name, value| %( #{name}="#{h value}") }.join
    %(<a#{attribute_string}>#{text}</a>)
  end

  def _link_body(text)
    text.is_a?(RDoc::CodeObject) ? full_name_for(text) : text
  end

  def link_to_if(condition, text, *args)
    condition ? link_to(text, *args) : _link_body(text)
  end

  def link_to_external(text, url, html_attributes = {})
    html_attributes = html_attributes.transform_keys(&:to_s)
    html_attributes = { "target" => "_blank", "class" => nil }.merge(html_attributes)
    html_attributes["class"] = [*html_attributes["class"], "external-link"].join(" ")

    link_to(text, url, html_attributes)
  end

  def short_name_for(named)
    named = named.name if named.is_a?(RDoc::CodeObject)
    "<code>#{h named}</code>"
  end

  def full_name_for(named)
    named = named.full_name if named.is_a?(RDoc::CodeObject)
    "<code>#{named.split(%r"(?<=./|.::)").map { |part| h part }.join("<wbr>")}</code>"
  end

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
