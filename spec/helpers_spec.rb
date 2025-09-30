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
          def hi(msg)
            puts "Hi, #{msg}!"
          end
        end
      RUBY

      source_code, source_url = @helpers.method_source_code_and_url(method)

      expected_source = <<~EXPECTED.chomp
        def hi(msg)
          puts &quot;Hi, \#{msg}!&quot;
        end
      EXPECTED
      _(source_code).must_include expected_source
      _(source_url).must_be_nil
    end
  end
end
