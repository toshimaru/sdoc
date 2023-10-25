require "spec_helper"

describe SDoc::SearchIndex do
  describe "#generate" do
    it "generates a search index for the given modules and their methods" do
      top_level = rdoc_top_level_for <<~RUBY
        # This is FooBar.
        class FooBar
          # This is #hoge_fuga.
          def hoge_fuga; end
        end
      RUBY

      ngrams = SDoc::SearchIndex.derive_ngrams("FooBar#hoge_fuga")

      search_index = SDoc::SearchIndex.generate(top_level.classes_and_modules)

      _(search_index.keys.sort).must_equal ["ngrams", "weights", "entries"].sort

      _(search_index["ngrams"].keys.sort).must_equal ngrams.sort
      _(search_index["ngrams"].values.max).must_equal search_index["weights"].length - 1

      _(search_index["entries"].length).must_equal 2
      search_index["entries"].each do |entry|
        _(entry.length).must_be :<=, 6
        _(entry[0]).must_be_kind_of Array # Fingerprint
        _(entry[1]).must_be :<, 1.0 # Tiebreaker bonus
      end

      module_entry, method_entry = search_index["entries"].sort_by { |entry| entry[4] ? 1 : 0 }

      # URL
      _(module_entry[2]).must_equal "classes/FooBar.html"
      _(method_entry[2]).must_equal "classes/FooBar.html#method-i-hoge_fuga"

      # Module name
      _(module_entry[3]).must_equal "FooBar"
      _(method_entry[3]).must_equal "FooBar"

      # Method signature
      _(module_entry[4]).must_be_nil
      _(method_entry[4]).must_equal "#hoge_fuga()"

      # Description
      _(module_entry[5]).must_equal "This is <code>FooBar</code>."
      _(method_entry[5]).must_equal "This is <code>hoge_fuga</code>."
    end
  end

  describe "#derive_ngrams" do
    it "returns ngrams for a given string" do
      expected = %w[abc bcx cxy xyz]
      _(SDoc::SearchIndex.derive_ngrams("abcxyz") & expected).must_equal expected
    end

    it "includes module-related ngrams" do
      ngrams = SDoc::SearchIndex.derive_ngrams("Abc::Xyz")

      _(ngrams).must_include ":Ab"
      _(ngrams).must_include ":Xy"

      _(ngrams.grep(/c:|::|[.(]/)).must_be_empty
    end

    it "includes method-related ngrams for instance methods" do
      ngrams = SDoc::SearchIndex.derive_ngrams("Abc#def_xyz")

      _(ngrams).must_include "#de"
      _(ngrams).must_include ".de"
      _(ngrams).must_include "yz("

      _(ngrams).must_include "f_x"
      _(ngrams).must_include "efx"
      _(ngrams).must_include "fxy"

      _(ngrams.grep(/c#/)).must_be_empty
    end

    it "includes method-related ngrams for singleton methods" do
      ngrams = SDoc::SearchIndex.derive_ngrams("Abc::def_xyz")

      _(ngrams).must_include ":de"
      _(ngrams).must_include ".de"
      _(ngrams).must_include "yz("

      _(ngrams.grep(/c:/)).must_be_empty
    end

    it "includes space delimiter ngrams" do
      ngrams = SDoc::SearchIndex.derive_ngrams("Abc::Def#xyz")

      _(ngrams).must_include " Ab"
      _(ngrams).must_include " A "
      _(ngrams).must_include ":A "

      _(ngrams).must_include " De"
      _(ngrams).must_include " D "
      _(ngrams).must_include ":D "

      _(ngrams).must_include " xy"
      _(ngrams).must_include " x "
      _(ngrams).must_include "#x "

      _(ngrams.grep(/[cfz] $/)).must_be_empty
    end

    it "includes acronym ngrams" do
      ngrams = SDoc::SearchIndex.derive_ngrams("AbcDef::StUvWxYz")

      _(ngrams).must_include ":AD"
      _(ngrams).must_include " AD"
      _(ngrams).must_include ":SU"
      _(ngrams).must_include " SU"
      _(ngrams).must_include "SUW"
      _(ngrams).must_include "UWY"

      _(ngrams.grep(/DS/)).must_be_empty
    end

    it "includes downcased ngrams except for acronym ngrams" do
      ngrams = SDoc::SearchIndex.derive_ngrams("AbcDef::StUvWxYz")

      ngrams.grep(/[A-Z]/).grep_v(/[A-Z]{2}/).each do |uppercase|
        _(ngrams).must_include uppercase.downcase
      end
    end
  end

  describe "#compile_ngrams" do
    it "assigns ngram bit positions based on ngram rarity" do
      base_ngrams = ("aaa".."zzz").take(4)
      ngram_sets = (0..3).map { |n| base_ngrams.drop(n) }

      _(SDoc::SearchIndex.compile_ngrams(ngram_sets)).
        must_equal base_ngrams.reverse.each_with_index.to_h
    end
  end

  describe "#generate_fingerprint" do
    it "returns an array of bytes with bits set for the given ngrams" do
      ngrams = ("aaa".."zzz").take(8)

      packed_positions = ngrams.each_with_index.to_h
      _(SDoc::SearchIndex.generate_fingerprint(ngrams, packed_positions)).must_equal [0b11111111]

      sparse_positions = ngrams.each_with_index.to_h { |ngram, i| [ngram, i * 8] }
      _(SDoc::SearchIndex.generate_fingerprint(ngrams, sparse_positions)).must_equal [1] * 8
    end

    it "omits trailing zero bytes" do
      _(SDoc::SearchIndex.generate_fingerprint(["xxx"], { "xxx" => 0, "yyy" => 100 })).must_equal [1]
    end
  end

  describe "#compute_bit_weights" do
    it "returns an array of weights" do
      _(SDoc::SearchIndex.compute_bit_weights({ "xxx" => 0, "yyy" => 1 })).must_equal [1, 1]
    end

    it "computes weights based on ngram content" do
      ngram_bit_positions = { "xxx" => 0, " xx" => 1, ":Xx" => 2, "#xx" => 3 }
      bit_weights = SDoc::SearchIndex.compute_bit_weights(ngram_bit_positions)

      _(bit_weights.length).must_equal ngram_bit_positions.length
      _(bit_weights.uniq).must_equal bit_weights
      _(bit_weights.sort).must_equal bit_weights
    end

    it "orders weights by bit position" do
      ngram_bit_positions = { "xxx" => 0, " xx" => 1, ":Xx" => 2, "#xx" => 3 }
      bit_weights = SDoc::SearchIndex.compute_bit_weights(ngram_bit_positions)

      reversed = ngram_bit_positions.reverse_each.to_h
      _(SDoc::SearchIndex.compute_bit_weights(reversed)).must_equal bit_weights

      inverted = ngram_bit_positions.transform_values { |pos| -pos + bit_weights.length }
      _(SDoc::SearchIndex.compute_bit_weights(inverted)).must_equal bit_weights.reverse
    end

    it "ignores alias ngrams" do
      _(SDoc::SearchIndex.compute_bit_weights({ "#xx" => 0, ".xx" => 0}).length).must_equal 1
    end
  end

  describe "#compute_tiebreaker_bonus" do
    it "returns a value much smaller than 1 (the value of a single matching ngram)" do
      _(SDoc::SearchIndex.compute_tiebreaker_bonus("X", nil, "")).must_be :<=, 0.1
    end

    it "favors short module names over long module names" do
      [
        ["X", "Xx"],
        ["Time", "ActiveSupport::TimeZone"],
        ["ActiveSupport::TimeZone", "ActiveSupport::TimeWithZone"],
      ].each do |short_name, long_name|
        short_name_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus(short_name, nil, "")
        long_name_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus(long_name, nil, "")

        _(short_name_bonus).must_be :>, long_name_bonus, "#{short_name} vs #{long_name}"
      end
    end

    it "favors short method names over long method names" do
      [
        ["x", "xx"],
        ["has_one", "has_many"],
        ["has_many", "has_and_belongs_to_many"],
      ].each do |short_name, long_name|
        short_name_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus("X", short_name, "")
        long_name_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus("X", long_name, "")

        _(short_name_bonus).must_be :>, long_name_bonus, "X##{short_name} vs X##{long_name}"
      end
    end

    it "favors long module + short method names over short module + long method names" do
      [
        [ ["ActiveRecord::Associations::ClassMethods", "has_many"],
          ["ActiveStorage::Attached::Model", "has_many_attached"] ],
        [ ["ActiveRecord::FinderMethods", "find_by"],
          ["ActiveRecord::Querying", "find_by_sql"] ],
      ].each do |long_short, short_long|
        long_short_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus(*long_short, "")
        short_long_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus(*short_long, "")

        _(long_short_bonus).must_be :>, short_long_bonus, "#{long_short.join "#"} vs #{short_long.join "#"}"
      end
    end

    it "favors methods with long documentation over methods with short documentation" do
      [
        [ ["X", "x", 2],
          ["Y", "x", 1] ],
        [ ["ActionView::Template", "render", 300],
          ["ActionView::Renderer", "render", 80] ],
        [ ["ActionController::Rendering", "render", 3000],
          ["ActionController::Renderer", "render", 80] ],
      ].each do |(*names1, long_doc_length), (*names2, short_doc_length)|
        long_doc_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus(*names1, "x" * long_doc_length)
        short_doc_bonus = SDoc::SearchIndex.compute_tiebreaker_bonus(*names2, "x" * short_doc_length)

        _(long_doc_bonus).must_be :>, short_doc_bonus,
          "#{names1.join "#"} w/ #{long_doc_length} chars vs #{names2.join "#"} w/ #{short_doc_length} chars"
      end
    end

    it "balances factors to produce desirable results" do
      [
        [ ["ActiveSupport::Deprecation", nil, 0],
          ["Module", "deprecate", 600] ],
        [ ["Pathname", "existence", 200],
          ["ActiveSupport::Callbacks::CallTemplate::InstanceExec1", "expand", 0] ],
        [ ["ActiveRecord::Associations::ClassMethods", "has_many", 12000],
          ["ActiveStorage::Attached::Model", "has_many_attached", 2000] ],
        [ ["ActiveRecord::FinderMethods", "find_by", 200],
          ["ActiveRecord::Querying", "find_by_sql", 2000] ],
        [ ["ActionController::Rendering", "render", 3000],
          ["ActionController::Renderer", "render", 100] ],
        [ ["ActionView::Helpers::RenderingHelper", "render", 900],
          ["ActionView::Template", "render", 300] ],
      ].each do |(*names1, doc_length1), (*names2, doc_length2)|
        bonus1 = SDoc::SearchIndex.compute_tiebreaker_bonus(*names1, "x" * doc_length1)
        bonus2 = SDoc::SearchIndex.compute_tiebreaker_bonus(*names2, "x" * doc_length2)

        _(bonus1).must_be :>, bonus2,
          "#{names1.join "#"} w/ #{doc_length1} chars vs #{names2.join "#"} w/ #{doc_length2} chars"
      end
    end
  end

  describe "#signature_for" do
    it "returns a given method's signature" do
      rdoc_method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", false)
        module Foo; def bar(x, y, z); end; end
      RUBY

      _(SDoc::SearchIndex.signature_for(rdoc_method)).must_equal "#bar(x, y, z)"
    end

    it "prepends '::' for class methods" do
      rdoc_method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", true)
        module Foo; def self.bar(x, y, z); end; end
      RUBY

      _(SDoc::SearchIndex.signature_for(rdoc_method)).must_equal "::bar(x, y, z)"
    end

    it "uses '(...)' to represent params for :call-seq: methods" do
      rdoc_method = rdoc_top_level_for(<<~RUBY).find_module_named("Foo").find_method("bar", false)
        module Foo
          # :method: bar
          # :call-seq:
          #   bar(x, y, z) -> result
          #   bar(&block) -> result
        end
      RUBY

      _(SDoc::SearchIndex.signature_for(rdoc_method)).must_equal "#bar(...)"
    end
  end

  describe "#truncate_description" do
    it "extracts text from the leading paragraph" do
      _(SDoc::SearchIndex.truncate_description("<p>leading</p><p>second</p>", 100)).
        must_equal "leading"

      _(SDoc::SearchIndex.truncate_description("<h1>heading</h1><p>leading</p>", 100)).
        must_equal "leading"
    end

    it "returns nil if there is no leading paragraph" do
      _(SDoc::SearchIndex.truncate_description("<pre>code</pre><p>explanation</p>", 100)).
        must_be_nil

      _(SDoc::SearchIndex.truncate_description("", 100)).
        must_be_nil
    end

    it "preserves HTML" do
      _(SDoc::SearchIndex.truncate_description("<p><em>emphatic</em> text</p>", 100)).
        must_equal "<em>emphatic</em> text"
    end

    it "strips link HTML" do
      _(SDoc::SearchIndex.truncate_description(%(<p><a href="/"><code>ref</code></a> link</p>), 100)).
        must_equal "<code>ref</code> link"
    end

    it "truncates inner text at word boundaries" do
      description = "<p>12345 <i>78</i>. <b>12, <i>5 - 9</i>.</b></p>"

      {
         8..10 => "12345...",
        11..14 => "12345 <i>78</i>...",
        15..17 => "12345 <i>78</i>. <b>12</b>...",
        18..19 => "12345 <i>78</i>. <b>12, <i>5</i></b>...",
        20..25 => "12345 <i>78</i>. <b>12, <i>5 - 9</i>.</b>",
      }.each do |range, expected|
        range.each do |limit|
          _(SDoc::SearchIndex.truncate_description(description, limit)).must_equal expected
        end
      end
    end

    it "treats <code> elements as a whole" do
      (5..8).each do |limit|
        _(SDoc::SearchIndex.truncate_description("<p>1 <code>345 789</code></p>", limit)).
          must_equal "1..."
      end

      _(SDoc::SearchIndex.truncate_description("<p>1 <code>345 789</code></p>", 9)).
        must_equal "1 <code>345 789</code>"
    end

    it "adds ellipsis after trailing colon" do
      _(SDoc::SearchIndex.truncate_description("<p>for example:</p>", 100)).
        must_equal "for example:..."
    end
  end
end
