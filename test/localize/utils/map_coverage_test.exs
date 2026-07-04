defmodule Localize.Utils.MapCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Map, as: UtilsMap

  describe "key transformers applied to a {key, value} tuple" do
    test "atomize_keys/2 transforms the key and nested map" do
      assert UtilsMap.atomize_keys({"a", %{"b" => 1}}) == {"a", %{b: 1}}
    end

    test "atomize_values/2 transforms nested binary values" do
      assert UtilsMap.atomize_values({"a", %{"b" => "c"}}) == {"a", %{"b" => :c}}
    end

    test "integerize_keys/2 transforms nested numeric keys" do
      assert UtilsMap.integerize_keys({"a", %{"1" => :x}}) == {"a", %{1 => :x}}
    end

    test "floatize_keys/2 transforms nested float keys" do
      assert UtilsMap.floatize_keys({"a", %{"1.5" => :x}}) == {"a", %{1.5 => :x}}
    end

    test "stringify_keys/2 transforms nested atom keys" do
      assert UtilsMap.stringify_keys({:a, %{b: 1}}) == {:a, %{"b" => 1}}
    end

    test "underscore_keys/2 underscores nested binary keys" do
      assert UtilsMap.underscore_keys({"aB", %{"cD" => 1}}) == {"aB", %{"c_d" => 1}}
    end
  end

  describe "bare values inside lists" do
    test "atomize_values/2 atomizes bare binary list elements" do
      assert UtilsMap.atomize_values(%{a: ["ok", 1]}) == %{a: [:ok, 1]}
    end

    test "stringify_values/2 stringifies bare atom list elements" do
      assert UtilsMap.stringify_values(%{a: [:x, 1]}) == %{a: ["x", 1]}
    end
  end

  describe "delete_in/2" do
    test "with a binary key on a map" do
      assert UtilsMap.delete_in(%{"a" => 1, "b" => 2}, "a") == %{"b" => 2}
    end

    test "with a binary key on a keyword list" do
      assert UtilsMap.delete_in([a: 1, b: 2], "a") == [a: 1, b: 2]
    end
  end

  describe "extract_strings/2" do
    test "ignores non-string scalar values in maps" do
      result = UtilsMap.extract_strings(%{a: "one", b: 2, c: :three})
      assert Enum.sort(result) == ["one"]
    end

    test "collects strings from nested maps" do
      result = UtilsMap.extract_strings(%{a: "one", d: %{e: "four"}})
      assert Enum.sort(result) == ["four", "one"]
    end

    test "collects strings from a list, skipping non-strings" do
      assert UtilsMap.extract_strings([["b"], "a", 1]) |> Enum.sort() == ["a", "b"]
    end
  end

  describe "deep_map/3 with a {key_function, value_function} pair" do
    defp upcase_key(key), do: String.upcase(key)

    defp double_integer(value) when is_integer(value), do: value * 2
    defp double_integer(value), do: value

    test "skip: scalar keeps the branch unprocessed" do
      nested = %{"a" => %{"b" => 1}, "skipme" => %{"e" => 4}}

      assert UtilsMap.deep_map(nested, {&upcase_key/1, &double_integer/1}, skip: "skipme") ==
               %{"A" => %{"B" => 2}, "SKIPME" => %{"e" => 4}}
    end

    test "reject: scalar removes the branch" do
      nested = %{"a" => %{"b" => 1}, "gone" => 5}

      assert UtilsMap.deep_map(nested, {&upcase_key/1, &double_integer/1}, reject: "gone") ==
               %{"A" => %{"B" => 2}}
    end

    test "only: list processes matching branches only" do
      nested = %{"a" => %{"b" => 1}, "d" => 3}

      assert UtilsMap.deep_map(nested, {&upcase_key/1, &double_integer/1}, only: ["d"]) ==
               %{"D" => 6, "a" => %{"b" => 1}}
    end

    test "except: list leaves matching branches alone" do
      nested = %{"a" => %{"b" => 1}, "d" => 3}

      assert UtilsMap.deep_map(nested, {&upcase_key/1, &double_integer/1}, except: ["a"]) ==
               %{"D" => 6, "a" => %{"B" => 2}}
    end

    test "skip: function keeps the branch unprocessed" do
      nested = %{"a" => %{"b" => 1}, "skipme" => %{"e" => 4}}

      skip_function = fn
        {key, _value} -> key == "skipme"
        _other -> false
      end

      assert UtilsMap.deep_map(nested, {&upcase_key/1, &double_integer/1}, skip: skip_function) ==
               %{"A" => %{"B" => 2}, "SKIPME" => %{"e" => 4}}
    end

    test "reject: function on leaf list elements removes them" do
      identity = fn key -> key end

      assert UtilsMap.deep_map(%{a: [1, 2]}, {identity, &double_integer/1},
               reject: fn value -> value == 2 end
             ) == %{a: [2]}
    end

    test "skip: function on leaf list elements keeps them unprocessed" do
      identity = fn key -> key end

      assert UtilsMap.deep_map(%{a: [1, 2]}, {identity, &double_integer/1},
               skip: fn value -> value == 2 end
             ) == %{a: [2, 2]}
    end
  end

  describe "deep_map/3 over lists" do
    defp upcase_binary(value) when is_binary(value), do: String.upcase(value)
    defp upcase_binary(value), do: value

    test "skip: scalar keeps matching elements unprocessed" do
      assert UtilsMap.deep_map(["a", ["b", "c"], "d"], &upcase_binary/1, skip: "a") ==
               ["a", ["B", "C"], "D"]
    end

    test "reject: scalar removes matching elements" do
      assert UtilsMap.deep_map(["a", ["b", "c"], "d"], &upcase_binary/1, reject: "d") ==
               ["A", ["B", "C"]]
    end

    test "filter: function processes matching elements" do
      assert UtilsMap.deep_map(["a", ["b", "c"], "d"], &upcase_binary/1,
               filter: fn value -> is_binary(value) end
             ) == ["A", ["B", "C"], "D"]
    end

    test "except: function leaves matching elements alone" do
      assert UtilsMap.deep_map(["a", ["b", "c"], "d"], &upcase_binary/1,
               except: fn value -> value == "a" end
             ) == ["a", ["B", "C"], "D"]
    end

    test "nil elements are preserved" do
      assert UtilsMap.deep_map([nil, "a"], &upcase_binary/1, []) == [nil, "A"]
    end
  end
end
