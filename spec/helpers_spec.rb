# frozen_string_literal: true

require "spec_helper"

describe SDoc::Helpers do
  before :each do
    @helpers = Class.new do
      include SDoc::Helpers

      attr_accessor :options
    end.new

    @helpers.options = RDoc::Options.new
  end

  describe "#link_to" do
    it "returns a link tag" do
      _(@helpers.link_to("Foo::Bar::Qux", "foo/bar/qux.html")).
        must_equal %(<a href="foo/bar/qux.html">Foo::Bar::Qux</a>)
    end

    it "supports HTML attributes" do
      _(@helpers.link_to("foo", "bar", class: "qux", "data-hoge": "fuga")).
        must_equal %(<a href="bar" class="qux" data-hoge="fuga">foo</a>)
    end

    it "escapes the HTML attributes" do
      _(@helpers.link_to("Foo", "foo", title: "Foo < Object")).
        must_equal %(<a href="foo" title="Foo &lt; Object">Foo</a>)
    end

    it "does not escape the link body" do
      _(@helpers.link_to("<code>Foo</code>", "foo")).
        must_equal %(<a href="foo"><code>Foo</code></a>)
    end

    it "uses the first argument as the URL when no URL is specified" do
      _(@helpers.link_to("foo/bar/qux.html")).
        must_equal %(<a href="foo/bar/qux.html">foo/bar/qux.html</a>)

      _(@helpers.link_to("foo/bar/qux.html", "data-hoge": "fuga")).
        must_equal %(<a href="foo/bar/qux.html" data-hoge="fuga">foo/bar/qux.html</a>)
    end

    it "uses #full_name_for when the text argument is an RDoc::CodeObject" do
      top_level = rdoc_top_level_for <<~RUBY
        module Foo; class Bar; def qux; end; end; end
      RUBY

      [
        top_level,
        top_level.find_module_named("Foo"),
        top_level.find_module_named("Foo::Bar"),
        top_level.find_module_named("Foo::Bar").find_method("qux", false),
      ].each do |code_object|
        _(@helpers.link_to(code_object, "url")).
          must_equal %(<a href="url">#{@helpers.full_name_for(code_object)}</a>)
      end
    end

    it "uses RDoc::CodeObject#path as the URL when URL argument is an RDoc::CodeObject" do
      top_level = rdoc_top_level_for <<~RUBY
        module Foo; class Bar; def qux; end; end; end
      RUBY

      [
        top_level,
        top_level.find_module_named("Foo"),
        top_level.find_module_named("Foo::Bar"),
        top_level.find_module_named("Foo::Bar").find_method("qux", false),
      ].each do |code_object|
        _(@helpers.link_to("text", code_object)).
          must_equal %(<a href="/#{code_object.path}">text</a>)
      end
    end

    it "uses .ref-link as the default class when creating a <code> link to an RDoc::CodeObject" do
      rdoc_module = rdoc_top_level_for(<<~RUBY).find_module_named("Foo::Bar")
        module Foo; module Bar; end
      RUBY

      _(@helpers.link_to(rdoc_module)).
        must_equal %(<a href="/#{rdoc_module.path}" class="ref-link">#{@helpers.full_name_for(rdoc_module)}</a>)

      _(@helpers.link_to("<code>Bar</code>", rdoc_module)).
        must_equal %(<a href="/#{rdoc_module.path}" class="ref-link"><code>Bar</code></a>)

      _(@helpers.link_to("<code>Bar</code>", rdoc_module, class: "other")).
        must_equal %(<a href="/#{rdoc_module.path}" class="other"><code>Bar</code></a>)

      _(@helpers.link_to("Jump to <code>Bar</code>", rdoc_module)).
        must_equal %(<a href="/#{rdoc_module.path}">Jump to <code>Bar</code></a>)
    end
  end

  describe "#link_to_if" do
    it "returns the link's HTML when the condition is true" do
      args = ["<code>Foo</code>", "foo", title: "Foo < Object"]
      _(@helpers.link_to_if(true, *args)).must_equal @helpers.link_to(*args)
    end

    it "returns the link's inner HTML when the condition is false" do
      _(@helpers.link_to_if(false, "<code>Foo</code>", "url")).must_equal "<code>Foo</code>"

      rdoc_module = rdoc_top_level_for(<<~RUBY).find_module_named("Foo::Bar")
        module Foo; class Bar; end; end
      RUBY

      _(@helpers.link_to_if(false, rdoc_module, "url")).must_equal @helpers.full_name_for(rdoc_module)
    end
  end

  describe "#method_source_code_and_url" do
    before :each do
      @helpers.options.github = true
    end

    it "returns source code and GitHub URL for a given RDoc::AnyMethod" do
      method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", false)
        module Foo # line 1
          def bar # line 2
            # line 3
          end
        end
      RUBY

      source_code, source_url = @helpers.method_source_code_and_url(method)
      _(source_code).must_match %r{# File .+\.rb, line 2\b}
      _(source_code).must_include "line 3"
      _(source_url).must_match %r{\Ahttps://github.com/.+\.rb#L2\z}
    end

    it "returns nil source code when given method is an RDoc::GhostMethod" do
      method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", false)
        module Foo # line 1
          ##
          # :method: bar
        end
      RUBY

      source_code, source_url = @helpers.method_source_code_and_url(method)

      _(source_code).must_be_nil
      _(source_url).must_match %r{\Ahttps://github.com/.+\.rb#L3\z}
    end

    it "returns nil source code when given method is an alias" do
      method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", false)
        module Foo # line 1
          def qux; end
          alias bar qux
        end
      RUBY

      source_code, source_url = @helpers.method_source_code_and_url(method)

      _(source_code).must_be_nil
      # Unfortunately, source_url is also nil because RDoc does not provide the
      # source code location in this case.
      _(source_url).must_be_nil
    end

    it "returns nil GitHub URL when options.github is false" do
      @helpers.options.github = false

      method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", false)
        module Foo # line 1
          def bar; end # line 2
        end
      RUBY

      source_code, source_url = @helpers.method_source_code_and_url(method)

      _(source_code).must_match %r{# File .+\.rb, line 2\b}
      _(source_url).must_be_nil
    end

    it "sanitizes source code" do
      @helpers.options.github = false

      method = rdoc_top_level_for(<<~'RUBY').find_module_named("Foo").find_method("hi", false)
        module Foo
          def hi(msg) = puts "Hi, #{msg}!"
        end
      RUBY

      source_code, source_url = @helpers.method_source_code_and_url(method)
      expected_source = <<~EXPECTED.chomp
        def hi(msg) = puts &quot;Hi, \#{msg}!&quot;
      EXPECTED
      _(source_code).must_include expected_source
      _(source_url).must_be_nil
    end

    describe "normalizing indentation" do
      it "normalizes the code" do
        method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo::Bar").find_method("baz", false)
          module Foo
            module Bar
                def baz
                    puts "hello"
                    if true
                      puts "world"
                    end
                end
            end
          end
        RUBY

        source_code, _source_url = @helpers.method_source_code_and_url(method)
        expected_source = <<~EXPECTED.chomp
          def baz
              puts &quot;hello&quot;
              if true
                puts &quot;world&quot;
              end
          end
        EXPECTED
        _(source_code).must_include expected_source
      end

      it "normalizes the code 2" do
        method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo::Bar").find_method("baz", false)
          module Foo
            module Bar
                def baz
                  puts "hello"
                    if true
                      puts "world"
                  end
              end
            end
          end
        RUBY

        source_code, _source_url = @helpers.method_source_code_and_url(method)
        expected_source = <<~EXPECTED.chomp
          def baz
            puts &quot;hello&quot;
              if true
                puts &quot;world&quot;
            end
          end
        EXPECTED
        _(source_code).must_include expected_source
      end

      it "normalizes the code 3" do
        method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", false)
          module Foo
              def bar
                  puts "hello"
                end
          end
        RUBY

        source_code, _source_url = @helpers.method_source_code_and_url(method)
        expected_source = <<~EXPECTED.chomp
          def bar
              puts &quot;hello&quot;
            end
        EXPECTED
        _(source_code).must_include expected_source
      end
    end
  end
end
