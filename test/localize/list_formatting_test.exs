defmodule Localize.ListFormattingTest do
  @moduledoc """
  Lists joined with CLDR's list patterns, through every public entry point.

  Expected values come from ECMA-402's `Intl.ListFormat` in Node 24 (ICU 77):
  the `conjunction`, `disjunction` and `unit` types in the long, short and
  narrow styles, which are Localize's `:standard`, `:or` and `:unit` list
  styles and their `_short` and `_narrow` forms. An empty list formats as the
  empty string.

  """

  use ExUnit.Case, async: true

  @cases [
    {:en, :standard, ["a", "b", "c"], "a, b, and c"},
    {:en, :standard, ["a", "b"], "a and b"},
    {:en, :standard, ["a"], "a"},
    {:en, :standard_short, ["a", "b", "c"], "a, b, & c"},
    {:en, :standard_narrow, ["a", "b", "c"], "a, b, c"},
    {:en, :or, ["a", "b", "c"], "a, b, or c"},
    {:en, :unit, ["a", "b", "c"], "a, b, c"},
    {:en, :unit_narrow, ["a", "b", "c"], "a b c"},
    {:fr, :standard, ["a", "b", "c"], "a, b et c"},
    {:de, :or, ["a", "b", "c", "d"], "a, b, c oder d"}
  ]

  test "list styles match ICU through to_string, to_parts and intersperse" do
    for {locale, style, items, expected} <- @cases do
      options = [list_style: style, locale: locale]
      label = {locale, style, items}

      assert {label, Localize.List.to_string(items, options)} == {label, {:ok, expected}}
      assert {label, Localize.List.to_string!(items, options)} == {label, expected}

      assert {:ok, parts} = Localize.List.to_parts(items, options)
      assert {label, Enum.map_join(parts, & &1.value)} == {label, expected}

      assert {label, Enum.map_join(Localize.List.to_parts!(items, options), & &1.value)} ==
               {label, expected}

      assert {:ok, interspersed} = Localize.List.intersperse(items, options)
      assert {label, Enum.join(interspersed)} == {label, expected}
      assert {label, Enum.join(Localize.List.intersperse!(items, options))} == {label, expected}
    end
  end

  test "the default options join a list in the default locale" do
    items = ["a", "b", "c"]

    assert Localize.List.to_string!(items) == "a, b, and c"
    assert {:ok, parts} = Localize.List.to_parts(items)
    assert Enum.map_join(parts, & &1.value) == "a, b, and c"
    assert Enum.map_join(Localize.List.to_parts!(items), & &1.value) == "a, b, and c"
    assert Enum.join(Localize.List.intersperse!(items)) == "a, b, and c"
  end

  test "an empty list formats as the empty string" do
    assert Localize.List.to_string([], locale: :en) == {:ok, ""}
  end
end
