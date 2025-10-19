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
