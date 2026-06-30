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
  end
end
