defmodule Localize.Message.SubstitutionTest do
  use ExUnit.Case, async: true

  alias Localize.Substitution

  # Localize.Substitution backs template interpolation for list,
  # number-range and transliteration patterns. The doctests live in
  # test/localize/substitution_test.exs; this file covers the
  # non-doctest clauses of parse/1 and substitute/2.

  describe "parse/1" do
    test "template with no markers is a single literal token" do
      assert Substitution.parse("no markers") == ["no markers"]
    end

    test "adjacent markers parse without literal tokens" do
      assert Substitution.parse("{0}{1}") == [0, 1]
    end

    test "markers may appear in any order" do
      assert Substitution.parse("{1} und {0}") == [1, " und ", 0]
    end

    test "three markers with literals between" do
      assert Substitution.parse("{0} a {1} b {2}") == [0, " a ", 1, " b ", 2]
    end

    test "only single-digit markers are recognized" do
      assert Substitution.parse("{12}") == ["{12}"]
    end
  end

  describe "substitute/2 — single parameter" do
    test "bare value with a lone marker" do
      assert Substitution.substitute("x", [0]) == ["x"]
    end

    test "literal-only template ignores the value" do
      assert Substitution.substitute("x", ["lit"]) == ["lit"]
      assert Substitution.substitute(["x"], ["lit"]) == ["lit"]
    end

    test "marker followed by a literal" do
      assert Substitution.substitute("x", [0, "!"]) == ["x", "!"]
      assert Substitution.substitute(["x"], [0, "!"]) == ["x", "!"]
    end

    test "literal followed by a marker" do
      assert Substitution.substitute("x", ["¡", 0]) == ["¡", "x"]
      assert Substitution.substitute(["x"], ["¡", 0]) == ["¡", "x"]
    end

    test "marker wrapped by literals" do
      assert Substitution.substitute("x", ["(", 0, ")"]) == ["(", "x", ")"]
    end
  end

  describe "substitute/2 — two and three parameters" do
    test "markers in order with a separator" do
      assert Substitution.substitute(["a", "b"], [0, " and ", 1]) == ["a", " and ", "b"]
    end

    test "markers in reverse order swap the values" do
      assert Substitution.substitute(["a", "b"], [1, " und ", 0]) == ["b", " und ", "a"]
    end

    test "adjacent markers" do
      assert Substitution.substitute(["a", "b"], [0, 1]) == ["a", "b"]
    end

    test "two markers with a trailing literal" do
      assert Substitution.substitute(["a", "b"], [0, "-", 1, "!"]) == ["a", "-", "b", "!"]
    end

    test "three markers with separators" do
      assert Substitution.substitute(["a", "b", "c"], [0, "-", 1, "-", 2]) ==
               ["a", "-", "b", "-", "c"]
    end
  end
end
