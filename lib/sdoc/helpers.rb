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

protected
  def group_name name
    if match = name.match(/^([a-z])/i)
      match[1].upcase
    else
      '#'
    end
  end
end
