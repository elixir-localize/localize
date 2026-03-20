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
end
