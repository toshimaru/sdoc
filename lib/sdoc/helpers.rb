module SDoc::Helpers
  require_relative "helpers/git"
  include ::SDoc::Helpers::Git

  # Strips out HTML tags from a given string.
  #
  # Example:
  #
  #   strip_tags("<strong>Hello world</strong>") => "Hello world"
  def strip_tags(text)
    text.gsub(%r{</?[^>]+?>}, "")
  end

  # Truncates a given string. It tries to take whole sentences to have
  # a meaningful description for SEO tags.
  #
  # The only available option is +:length+ which defaults to 200.
  def truncate(text, options = {})
    if text
      length = options.fetch(:length, 200)
      stop   = text.rindex(".", length - 1) || length

      "#{text[0, stop]}."
    end
  end

  def method_source_code_and_url(rdoc_method)
    source_code = rdoc_method.tokens_to_s if rdoc_method.token_stream

    if source_code&.match(/File\s(\S+), line (\d+)/)
      source_url = github_url(Regexp.last_match(1), line: Regexp.last_match(2))
    end

    [rdoc_method.instance_of?(RDoc::GhostMethod) ? nil : h(source_code), source_url]
  end
end
