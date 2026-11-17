defmodule Localize.CollationTest do
  use ExUnit.Case

  doctest Localize.Collation
  doctest Localize.Collation.Element
  doctest Localize.Collation.Options
  doctest Localize.Collation.SortKey
  doctest Localize.Collation.Table
  doctest Localize.Collation.Normalizer
  doctest Localize.Collation.Numeric
  doctest Localize.Collation.Variable
  doctest Localize.Collation.ImplicitWeights
  doctest Localize.Collation.Sensitive
  doctest Localize.Collation.Insensitive

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  describe "compare/3" do
    test "identical strings are equal" do
      assert Localize.Collation.compare("hello", "hello") == :eq
    end

    test "basic Latin ordering" do
      assert Localize.Collation.compare("a", "b") == :lt
      assert Localize.Collation.compare("b", "a") == :gt
      assert Localize.Collation.compare("abc", "abd") == :lt
    end

    test "case ordering at tertiary level" do
      assert Localize.Collation.compare("a", "A") == :lt
      assert Localize.Collation.compare("A", "a") == :gt
    end

    test "case ignored at secondary strength" do
      assert Localize.Collation.compare("a", "A", strength: :secondary) == :eq
      assert Localize.Collation.compare("abc", "ABC", strength: :secondary) == :eq
    end

    test "accent ordering" do
      assert Localize.Collation.compare("e", "é") == :lt
      assert Localize.Collation.compare("é", "e") == :gt
    end

    test "accents ignored at primary strength" do
      assert Localize.Collation.compare("e", "é", strength: :primary) == :eq
      assert Localize.Collation.compare("cafe", "café", strength: :primary) == :eq
    end

    test "shorter string sorts before longer when prefix matches" do
      assert Localize.Collation.compare("abc", "abcd") == :lt
    end

    test "space sorts before letters" do
      assert Localize.Collation.compare(" ", "a") == :lt
    end

    test "digits sort before letters" do
      assert Localize.Collation.compare("1", "a") == :lt
    end

    test "casing option" do
      assert Localize.Collation.compare("a", "A", casing: :insensitive) == :eq
      assert Localize.Collation.compare("a", "A", casing: :sensitive) == :lt
    end
  end

  describe "sort/2" do
    test "sorts basic Latin strings" do
      assert Localize.Collation.sort(["c", "a", "b"]) == ["a", "b", "c"]
    end

    test "sorts with accents" do
      result = Localize.Collation.sort(["é", "e", "ê", "ë"])
      assert hd(result) == "e"
    end

    test "sorts mixed case" do
      result = Localize.Collation.sort(["B", "a", "b", "A"])
      assert result == ["a", "A", "b", "B"]
    end

    test "sorts empty strings" do
      assert Localize.Collation.sort(["b", "", "a"]) == ["", "a", "b"]
    end
  end

  describe "sort_key/2" do
    test "returns binary" do
      assert is_binary(Localize.Collation.sort_key("hello"))
    end

    test "sort keys maintain ordering" do
      key_a = Localize.Collation.sort_key("a")
      key_b = Localize.Collation.sort_key("b")
      assert key_a < key_b
    end

    test "identical strings produce identical sort keys" do
      assert Localize.Collation.sort_key("hello") == Localize.Collation.sort_key("hello")
    end

    test "empty string produces a sort key" do
      key = Localize.Collation.sort_key("")
      assert is_binary(key)
    end
  end

  describe "comparator modules" do
    test "Insensitive comparator" do
      assert Enum.sort(["AAAA", "AAAa"], Localize.Collation.Insensitive) == ["AAAA", "AAAa"]
    end

    test "Sensitive comparator" do
      assert Enum.sort(["AAAA", "AAAa"], Localize.Collation.Sensitive) == ["AAAa", "AAAA"]
    end
  end

  describe "territory-specific tailorings" do
    # fr-CA's tailoring is keyed by language-territory and consists
    # solely of the `[backwards 2]` option override; plain fr has no
    # tailoring at all. Resolution must start from the most specific
    # identifier or the override is silently lost.
    test "fr-CA enables backwards accent comparison from locale data" do
      words = ["côte", "coté", "cote", "côté"]

      assert Localize.Collation.sort(words, locale: "fr-CA") ==
               ["cote", "côte", "coté", "côté"]

      assert Localize.Collation.sort(words, locale: "fr-CA") ==
               Localize.Collation.sort(words, backwards: true)

      # Plain fr does not sort backwards
      assert Localize.Collation.sort(words, locale: "fr") ==
               ["cote", "coté", "côte", "côté"]
    end

    test "a territory without its own tailoring falls back to the language" do
      # de-AT has no tailoring of its own; the parent chain resolves de
      assert Localize.Collation.sort(["äpfel", "apfel"], locale: "de-AT") ==
               Localize.Collation.sort(["äpfel", "apfel"], locale: "de")
    end
  end

  describe "keyword options and an options struct" do
    @words ["côte", "cote", "Côte", "coté", "file10", "file2", "Zebra", "apple"]

    test "a struct built once gives the order the keyword list gives" do
      for {keywords, options} <- [
            {[locale: "und-u-kn"], Localize.Collation.Options.from_locale("und-u-kn")},
            {[strength: :secondary], Localize.Collation.Options.new(strength: :secondary)},
            {[locale: "fr-CA"], Localize.Collation.Options.from_locale("fr-CA")}
          ] do
        assert Localize.Collation.sort(@words, keywords) ==
                 Localize.Collation.sort(@words, options)

        for a <- @words, b <- @words do
          assert Localize.Collation.compare(a, b, keywords) ==
                   Localize.Collation.compare(a, b, options)
        end
      end
    end

    test "invalid options are reported before invalid strings" do
      assert {:error, %Localize.InvalidValueError{value: :bogus}} =
               Localize.Collation.compare(:a, "b", strength: :bogus)

      assert {:error, %Localize.InvalidValueError{} = error} =
               Localize.Collation.compare(:a, "b", Localize.Collation.Options.new())

      assert error.value == :a
    end

    test "a struct with strings of the wrong type is an error" do
      options = Localize.Collation.Options.new()

      assert {:error, %Localize.InvalidValueError{value: 1}} =
               Localize.Collation.compare("a", 1, options)

      assert {:error, %Localize.InvalidValueError{value: "abc"}} =
               Localize.Collation.sort("abc", options)

      assert {:error, _exception} = Localize.Collation.sort(["a", 1], options)
    end

    test "options that are neither a keyword list nor a struct are an error" do
      assert {:error, _exception} = Localize.Collation.compare("a", "b", %{})
      assert {:error, _exception} = Localize.Collation.sort(["a"], :options)
    end
  end
end
