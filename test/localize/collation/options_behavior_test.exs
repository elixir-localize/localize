defmodule Localize.Collation.OptionsBehaviorTest do
  # End-to-end behavior of each public collation option through
  # Localize.Collation.compare/3, sort/2 and sort_key/2, pinned to
  # the pure Elixir backend.
  use ExUnit.Case, async: true

  alias Localize.Collation

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  describe "strength option" do
    test "primary strength ignores accents and case" do
      assert Collation.compare("a", "á", strength: :primary, backend: :elixir) == :eq
      assert Collation.compare("a", "A", strength: :primary, backend: :elixir) == :eq
      assert Collation.compare("a", "b", strength: :primary, backend: :elixir) == :lt
    end

    test "secondary strength sees accents but not case" do
      assert Collation.compare("a", "á", strength: :secondary, backend: :elixir) == :lt
      assert Collation.compare("a", "A", strength: :secondary, backend: :elixir) == :eq
    end

    test "tertiary strength sees case" do
      assert Collation.compare("a", "A", strength: :tertiary, backend: :elixir) == :lt
    end

    test "quaternary strength restores shifted variable distinctions" do
      options = [alternate: :shifted, backend: :elixir]

      assert Collation.compare("ab", "a-b", options) == :eq
      assert Collation.compare("ab", "a-b", [{:strength, :quaternary} | options]) == :gt
    end

    test "identical strength equates canonically equivalent strings when normalizing" do
      precomposed = "é"
      decomposed = "e\u0301"

      options = [strength: :identical, normalization: true, backend: :elixir]
      assert Collation.compare(precomposed, decomposed, options) == :eq
    end
  end

  describe "alternate and ignore_punctuation options" do
    test "shifted makes punctuation ignorable at tertiary strength" do
      assert Collation.compare("ab", "a-b", alternate: :shifted, backend: :elixir) == :eq
      assert Collation.compare("ab", "a!b", alternate: :shifted, backend: :elixir) == :eq
    end

    test "non_ignorable keeps punctuation significant" do
      assert Collation.compare("ab", "a-b", alternate: :non_ignorable, backend: :elixir) == :gt
    end

    test "ignore_punctuation is shorthand for shifted" do
      assert Collation.compare("ab", "a-b", ignore_punctuation: true, backend: :elixir) == :eq
      assert Collation.compare("co-op", "coop", ignore_punctuation: true, backend: :elixir) == :eq
    end
  end

  describe "backwards option (French accent ordering)" do
    test "reverses secondary weight comparison" do
      assert Collation.sort(["côte", "coté"], backend: :elixir) == ["coté", "côte"]

      assert Collation.sort(["côte", "coté"], backwards: true, backend: :elixir) ==
               ["côte", "coté"]
    end
  end

  describe "case_first option" do
    test "upper first sorts uppercase before lowercase" do
      assert Collation.sort(["a", "A"], case_first: :upper, backend: :elixir) == ["A", "a"]
    end

    test "lower first sorts lowercase before uppercase" do
      assert Collation.sort(["A", "a"], case_first: :lower, backend: :elixir) == ["a", "A"]
    end
  end

  describe "case_level option" do
    test "adds a case level even at primary strength" do
      options = [strength: :primary, backend: :elixir]

      assert Collation.compare("a", "A", options) == :eq
      assert Collation.compare("a", "A", [{:case_level, true} | options]) == :lt
    end
  end

  describe "numeric option" do
    test "compares digit runs by numeric value" do
      assert Collation.compare("a2", "a10", numeric: true, backend: :elixir) == :lt
      assert Collation.compare("a2", "a10", backend: :elixir) == :gt
    end

    test "sorts version-like strings numerically" do
      versions = ["item10", "item2", "item1"]

      assert Collation.sort(versions, numeric: true, backend: :elixir) ==
               ["item1", "item2", "item10"]
    end
  end

  describe "normalization option" do
    test "treats precomposed and decomposed input identically" do
      assert Collation.compare("é", "e\u0301", normalization: true, backend: :elixir) == :eq
    end
  end

  describe "locale option forms" do
    test "accepts a LanguageTag struct" do
      {:ok, tag} = Localize.validate_locale("en-u-ks-level2")
      assert Collation.compare("a", "A", locale: tag) == :eq
    end

    test "accepts an atom locale" do
      assert Collation.compare("a", "A", locale: :"en-u-ks-level2") == :eq
    end

    test "the :type option matches the -u-co- extension" do
      assert Collation.compare("白", "北", locale: "zh", type: :pinyin) ==
               Collation.compare("白", "北", locale: "zh-u-co-pinyin")
    end
  end

  describe "sort_key/2 input forms" do
    test "accepts a codepoint list" do
      string_key = Collation.sort_key("abc", backend: :elixir)
      list_key = Collation.sort_key([?a, ?b, ?c], backend: :elixir)

      assert string_key == list_key
    end

    test "normalizes codepoint lists when requested" do
      precomposed = Collation.sort_key([0x00E9], normalization: true, backend: :elixir)
      decomposed = Collation.sort_key([?e, 0x0301], normalization: true, backend: :elixir)

      assert precomposed == decomposed
    end

    test "accepts a resolved Options struct" do
      options = Localize.Collation.Options.new(strength: :primary, backend: :elixir)

      assert Collation.sort_key("a", options) == Collation.sort_key("á", options)
    end
  end
end
