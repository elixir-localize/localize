defmodule Localize.Utils.MapTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Map, as: MapUtils

  doctest Localize.Utils.Map

  defp stringify_atom_keys_function do
    fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      other -> other
    end
  end

  describe "identity/1" do
    test "returns the argument unchanged" do
      assert MapUtils.identity(:anything) == :anything
      assert MapUtils.identity(%{a: 1}) == %{a: 1}
    end
  end

  describe "deep_map/3 options" do
    test "skip keeps the branch but does not process it" do
      map = %{a: :a, b: %{c: :c}}

      assert MapUtils.deep_map(map, stringify_atom_keys_function(), skip: :b) ==
               %{"a" => :a, "b" => %{c: :c}}
    end

    test "reject omits the branch entirely" do
      map = %{a: :a, b: %{c: :c}}

      assert MapUtils.deep_map(map, stringify_atom_keys_function(), reject: :b) ==
               %{"a" => :a}
    end

    test "filter processes only the matching branch" do
      map = %{a: :a, b: %{c: :c}}

      assert MapUtils.deep_map(map, stringify_atom_keys_function(), filter: :b) ==
               %{:a => :a, "b" => %{"c" => :c}}
    end

    test "level as a range limits which levels are processed" do
      map = %{a: 1, b: %{c: 2}}

      assert MapUtils.deep_map(map, stringify_atom_keys_function(), level: 2..2) ==
               %{a: 1, b: %{"c" => 2}}
    end

    test "check functions are honoured for only" do
      map = %{a: 1, b: 2}
      only_b = fn {key, _value} -> key == :b end

      assert MapUtils.deep_map(map, stringify_atom_keys_function(), only: only_b) ==
               %{:a => 1, "b" => 2}
    end

    test "lists of maps are traversed" do
      assert MapUtils.deep_map([%{a: 1}, %{b: 2}], stringify_atom_keys_function()) ==
               [%{"a" => 1}, %{"b" => 2}]
    end

    test "structs are returned unchanged" do
      date = ~D[2026-07-04]
      assert MapUtils.deep_map(date, stringify_atom_keys_function()) == date
    end

    test "a {key_function, value_function} pair is applied to keys and values" do
      map = %{a: :a, b: %{c: :c}}
      pair = {&Atom.to_string/1, &MapUtils.identity/1}

      assert MapUtils.deep_map(map, pair, []) == %{"a" => :a, "b" => %{"c" => :c}}
    end

    test "a {key_function, value_function} pair honours skip" do
      map = %{a: :a, b: %{c: :c}}
      pair = {&Atom.to_string/1, &MapUtils.identity/1}

      assert MapUtils.deep_map(map, pair, skip: :b) == %{"a" => :a, "b" => %{c: :c}}
    end

    test "raises InvalidValueError for a non-function transformer" do
      assert_raise Localize.InvalidValueError, fn ->
        MapUtils.deep_map(%{a: 1}, :not_a_function)
      end
    end

    test "raises InvalidValueError for an invalid level option" do
      assert_raise Localize.InvalidValueError, fn ->
        MapUtils.deep_map(%{a: 1}, &MapUtils.identity/1, level: :bad)
      end
    end
  end

  describe "atomize_keys/2" do
    test "converts only existing atoms when only_existing: true" do
      assert MapUtils.atomize_keys(%{"x" => %{"y" => 1}}, only_existing: true) ==
               %{x: %{y: 1}}
    end

    test "leaves unknown keys as strings when only_existing: true" do
      key = "localize_map_test_key_that_does_not_exist"
      assert MapUtils.atomize_keys(%{key => 1}, only_existing: true) == %{key => 1}
    end

    test "returns non-map, non-list input unchanged" do
      assert MapUtils.atomize_keys(:other, []) == :other
    end
  end

  describe "atomize_values/2" do
    test "converts string values to atoms" do
      assert MapUtils.atomize_values(%{a: "ok"}) == %{a: :ok}
    end

    test "leaves unknown values as strings when only_existing: true" do
      value = "localize_map_test_value_that_does_not_exist"
      assert MapUtils.atomize_values(%{a: value}, only_existing: true) == %{a: value}
    end
  end

  describe "integerize and floatize" do
    test "integerize_keys leaves non-integer keys unchanged" do
      assert MapUtils.integerize_keys(%{"1" => "a", "x" => "b"}) ==
               %{1 => "a", "x" => "b"}
    end

    test "integerize_values leaves non-integer values unchanged" do
      assert MapUtils.integerize_values(%{a: "1", b: "x"}) == %{a: 1, b: "x"}
    end

    test "floatize_keys leaves unparseable keys unchanged" do
      assert MapUtils.floatize_keys(%{"1.5" => "a", "x" => "b"}) ==
               %{1.5 => "a", "x" => "b"}
    end

    test "floatize_values leaves unparseable values unchanged" do
      assert MapUtils.floatize_values(%{a: "1.5", b: "x"}) == %{a: 1.5, b: "x"}
    end
  end

  describe "stringify_keys/2 and stringify_values/2" do
    test "stringify_keys converts atom keys at depth" do
      assert MapUtils.stringify_keys(%{a: %{b: 1}}) == %{"a" => %{"b" => 1}}
    end

    test "stringify_values converts atom values" do
      assert MapUtils.stringify_values(%{a: :one, b: "two"}) == %{a: "one", b: "two"}
    end
  end

  describe "underscore_keys/2 and underscore/1" do
    test "underscore_keys converts camelCase keys at depth" do
      assert MapUtils.underscore_keys(%{"aKey" => %{"thisOne" => 1}}) ==
               %{"a_key" => %{"this_one" => 1}}
    end

    test "underscore handles dashes and dots" do
      assert MapUtils.underscore("thisOne-that.Other") == "this_one_that/other"
    end

    test "underscore returns non-binary input unchanged" do
      assert MapUtils.underscore(:not_a_binary) == :not_a_binary
    end
  end

  describe "rename_keys/4 and remove_leading_underscores/2" do
    test "rename_keys renames at any depth" do
      assert MapUtils.rename_keys(%{"a" => %{"from" => 1}}, "from", "to") ==
               %{"a" => %{"to" => 1}}
    end

    test "remove_leading_underscores strips leading underscores at depth" do
      assert MapUtils.remove_leading_underscores(%{"_a" => %{"_b" => 1}}) ==
               %{"a" => %{"b" => 1}}
    end
  end

  describe "deep_merge/3 and merge_map_list/2" do
    test "deep_merge recursively merges nested maps preferring the right side" do
      left = %{a: %{b: 1, c: 2}, d: 3}
      right = %{a: %{b: 10}, e: 4}

      assert MapUtils.deep_merge(left, right) == %{a: %{b: 10, c: 2}, d: 3, e: 4}
    end

    test "merge_map_list merges a list of maps" do
      assert MapUtils.merge_map_list([%{a: %{b: 1}}, %{a: %{c: 2}}, %{d: 3}]) ==
               %{a: %{b: 1, c: 2}, d: 3}
    end

    test "merge_map_list of an empty list returns an empty list" do
      assert MapUtils.merge_map_list([]) == []
    end

    test "combine_list_resolver concatenates list values" do
      assert MapUtils.combine_list_resolver(:key, [1], [2]) == [1, 2]
    end
  end

  describe "delete_in/2" do
    test "deletes keys at any depth in a map" do
      assert MapUtils.delete_in(%{a: %{b: 1, c: 2}, b: 3}, [:b]) == %{a: %{c: 2}}
    end

    test "accepts a binary key for a map" do
      assert MapUtils.delete_in(%{"a" => 1, "b" => 2}, "a") == %{"b" => 2}
    end

    test "deletes keys in a keyword list" do
      assert MapUtils.delete_in([a: 1, b: 2], [:a]) == [b: 2]
    end

    test "returns other terms unchanged" do
      assert MapUtils.delete_in(:other, [:a]) == :other
    end
  end

  describe "invert/2" do
    test "inverts a map with list values" do
      assert MapUtils.invert(%{a: [1, 2]}) == %{1 => :a, 2 => :a}
    end

    test "keeps duplicates when duplicates: :keep" do
      inverted = MapUtils.invert(%{a: [1, 2], b: [2, 3]}, duplicates: :keep)

      assert Enum.sort(inverted[1]) == [:a]
      assert Enum.sort(inverted[2]) == [:a, :b]
      assert Enum.sort(inverted[3]) == [:b]
    end

    test "keeps the shortest duplicate when duplicates: :shortest" do
      assert MapUtils.invert(%{"ab" => "x", "abcd" => "x"}, duplicates: :shortest) ==
               %{"x" => "ab"}
    end

    test "keeps the longest duplicate when duplicates: :longest" do
      assert MapUtils.invert(%{ab: "x", abcd: "x"}, duplicates: :longest) ==
               %{"x" => :abcd}
    end
  end

  describe "extract_strings/2 and prune/2" do
    test "extract_strings finds strings in nested maps and lists" do
      map = %{a: "one", b: %{c: "two", d: [%{e: "three"}, "four"]}}

      assert map |> MapUtils.extract_strings() |> Enum.sort() ==
               ["four", "one", "three", "two"]
    end

    test "extract_strings of an empty list is an empty list" do
      assert MapUtils.extract_strings([]) == []
    end

    test "prune removes branches for which the function returns true" do
      pruner = fn
        {key, _value} -> key == :a
        _other -> false
      end

      assert MapUtils.prune(%{a: %{b: 1}, keep: 2}, pruner) == %{keep: 2}
    end
  end

  describe "from_keyword/1" do
    test "converts a keyword list to a map" do
      assert MapUtils.from_keyword(a: 1) == %{a: 1}
    end

    test "converts an empty list to an empty map" do
      assert MapUtils.from_keyword([]) == %{}
    end
  end
end
