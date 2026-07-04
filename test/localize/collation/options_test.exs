defmodule Localize.Collation.OptionsTest do
  use ExUnit.Case

  alias Localize.Collation.Options

  describe "new/1" do
    test "creates default options" do
      options = Options.new()
      assert options.strength == :tertiary
      assert options.alternate == :non_ignorable
      assert options.backwards == false
      assert options.normalization == false
      assert options.case_level == false
      assert options.case_first == false
      assert options.numeric == false
      assert options.reorder == []
      assert options.max_variable == :punct
      assert options.type == :standard
    end

    test "accepts keyword options" do
      options = Options.new(strength: :primary, backwards: true)
      assert options.strength == :primary
      assert options.backwards == true
    end

    test "wraps a bare reorder atom in a list" do
      assert Options.new(reorder: :Grek).reorder == [:Grek]
      assert Options.new(reorder: [:Grek, :Cyrl]).reorder == [:Grek, :Cyrl]
    end

    test "ignore_accents sets primary strength unless strength is given" do
      assert Options.new(ignore_accents: true).strength == :primary
      assert Options.new(ignore_accents: true, strength: :tertiary).strength == :tertiary
      assert Options.new(ignore_accents: false).strength == :tertiary
    end

    test "ignore_case sets secondary strength unless strength is given" do
      assert Options.new(ignore_case: true).strength == :secondary
      assert Options.new(ignore_case: true, strength: :primary).strength == :primary
      assert Options.new(ignore_case: false).strength == :tertiary
    end

    test "ignore_punctuation defaults alternate to shifted" do
      options = Options.new(ignore_punctuation: true)
      assert options.alternate == :shifted
      assert options.strength == :tertiary

      overridden = Options.new(ignore_punctuation: true, alternate: :non_ignorable)
      assert overridden.alternate == :non_ignorable
    end

    test "casing :insensitive sets secondary strength unless strength is given" do
      assert Options.new(casing: :insensitive).strength == :secondary
      assert Options.new(casing: :insensitive, strength: :primary).strength == :primary
    end

    test "casing :sensitive keeps the default strength" do
      assert Options.new(casing: :sensitive).strength == :tertiary
    end

    test "invalid casing raises InvalidValueError" do
      assert_raise Localize.InvalidValueError, fn ->
        Options.new(casing: :sometimes)
      end
    end
  end

  describe "from_locale/1" do
    test "parses strength" do
      options = Options.from_locale("en-u-ks-level1")
      assert options.strength == :primary

      options = Options.from_locale("en-u-ks-level2")
      assert options.strength == :secondary

      options = Options.from_locale("en-u-ks-identic")
      assert options.strength == :identical
    end

    test "parses alternate" do
      options = Options.from_locale("en-u-ka-shifted")
      assert options.alternate == :shifted

      options = Options.from_locale("en-u-ka-noignore")
      assert options.alternate == :non_ignorable
    end

    test "parses backwards (French accents)" do
      options = Options.from_locale("fr-u-kb-true")
      assert options.backwards == true
    end

    test "parses case_first" do
      options = Options.from_locale("en-u-kf-upper")
      assert options.case_first == :upper

      options = Options.from_locale("en-u-kf-lower")
      assert options.case_first == :lower
    end

    test "parses numeric" do
      options = Options.from_locale("en-u-kn-true")
      assert options.numeric == true
    end

    test "parses max_variable" do
      options = Options.from_locale("en-u-kv-space")
      assert options.max_variable == :space

      options = Options.from_locale("en-u-kv-currency")
      assert options.max_variable == :currency
    end

    test "parses collation type" do
      options = Options.from_locale("de-u-co-phonebk")
      assert options.type == :phonebook
    end

    test "parses multiple options" do
      options = Options.from_locale("en-u-ks-level2-ka-shifted-kn-true")
      assert options.strength == :secondary
      assert options.alternate == :shifted
      assert options.numeric == true
    end

    test "handles locale without -u- extension" do
      options = Options.from_locale("en")
      assert options == Options.new()
    end

    test "a string, atom, and equivalent language tag yield the same options" do
      for locale <- ["da", "en-u-ks-level2", "pt_BR", "iw"] do
        {:ok, tag} = Localize.validate_locale(locale)

        assert Options.from_locale(locale) == Options.from_locale(tag)
        assert Options.from_locale(locale) == Options.from_locale(String.to_atom(locale))
      end
    end

    test "canonicalizes legacy aliases before resolving defaults" do
      # `iw` is the legacy alias for `he`; both must resolve identically.
      assert Options.from_locale("iw") == Options.from_locale("he")
    end

    test "parses all strength levels including level4" do
      assert Options.from_locale("en-u-ks-level3").strength == :tertiary
      assert Options.from_locale("en-u-ks-level4").strength == :quaternary
    end

    test "unknown strength value defaults to tertiary" do
      assert Options.from_locale("en-u-ks-bogus").strength == :tertiary
    end

    test "unknown alternate value defaults to non_ignorable" do
      assert Options.from_locale("en-u-ka-bogus").alternate == :non_ignorable
    end

    test "parses normalization (kk) and case_level (kc)" do
      assert Options.from_locale("en-u-kk-true").normalization == true
      assert Options.from_locale("en-u-kk-false").normalization == false
      assert Options.from_locale("en-u-kc-true").case_level == true
    end

    test "parses case_first false and unknown values" do
      assert Options.from_locale("en-u-kf-false").case_first == false
      assert Options.from_locale("en-u-kf-bogus").case_first == false
    end

    test "a bare boolean key without a value means true" do
      assert Options.from_locale("en-u-kn").numeric == true
    end

    test "parses reorder codes from the kr key" do
      assert Options.from_locale("en-u-kr-latn-cyrl").reorder == [:latn, :cyrl]
    end

    test "parses all max_variable values" do
      assert Options.from_locale("en-u-kv-punct").max_variable == :punct
      assert Options.from_locale("en-u-kv-symbol").max_variable == :symbol
      assert Options.from_locale("en-u-kv-bogus").max_variable == :punct
    end

    test "parses the remaining collation types" do
      assert Options.from_locale("en-u-co-search").type == :search
      assert Options.from_locale("en-u-co-standard").type == :standard
      assert Options.from_locale("zh-u-co-pinyin").type == :pinyin
      assert Options.from_locale("zh-u-co-stroke").type == :stroke
      assert Options.from_locale("zh-u-co-zhuyin").type == :zhuyin
      assert Options.from_locale("zh-u-co-unihan").type == :unihan
      assert Options.from_locale("es-u-co-trad").type == :traditional
      assert Options.from_locale("ko-u-co-searchjl").type == :searchjl
      assert Options.from_locale("en-u-co-eor").type == :eor
    end

    test "unknown collation types default to :standard without interning atoms" do
      assert Options.from_locale("en-u-co-fantasy").type == :standard
    end

    test "unknown -u- keys are ignored" do
      options = Options.from_locale("en-u-zz-what")
      assert options == Options.new()
    end

    test "u extension parsing stops at a following singleton" do
      # The raw parser must not consume subtags beyond the -u- extension.
      options = Options.from_locale("en-u-ks-level2-t")
      assert options.strength == :secondary
    end
  end

  describe "max_variable_primary/1" do
    test "returns the boundary for every max_variable setting" do
      assert Options.max_variable_primary(%Options{max_variable: :space}) == 0x0209
      assert Options.max_variable_primary(%Options{max_variable: :punct}) == 0x0B61
      assert Options.max_variable_primary(%Options{max_variable: :symbol}) == 0x0EE3
      assert Options.max_variable_primary(%Options{max_variable: :currency}) == 0x0EFF
    end
  end

  describe "nif_compatible?/1" do
    test "default options are compatible" do
      assert Options.nif_compatible?(Options.new())
    end

    test "a tailoring overlay requires the Elixir backend" do
      refute Options.nif_compatible?(%Options{tailoring: %{}})
    end

    test "a non-punct max_variable requires the Elixir backend" do
      refute Options.nif_compatible?(Options.new(max_variable: :space))
      refute Options.nif_compatible?(Options.new(max_variable: :currency))
    end

    test "unsupported reorder codes require the Elixir backend" do
      refute Options.nif_compatible?(Options.new(reorder: [:Xxxx]))
      assert Options.nif_compatible?(Options.new(reorder: [:Grek, :Latn]))
    end
  end
end
