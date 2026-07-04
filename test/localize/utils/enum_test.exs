defmodule Localize.Utils.EnumTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Enum, as: EnumUtils

  doctest Localize.Utils.Enum

  describe "reduce_peeking/3" do
    test "halts when the reducer returns a halt tuple" do
      result =
        EnumUtils.reduce_peeking([1, 2, 3, 4], 0, fn head, _tail, accumulator ->
          if head >= 3 do
            {:halt, accumulator}
          else
            {:cont, accumulator + head}
          end
        end)

      assert result == 3
    end

    test "passes the remaining tail to the reducer" do
      result =
        EnumUtils.reduce_peeking([:a, :b, :c], [], fn head, tail, accumulator ->
          {:cont, [{head, tail} | accumulator]}
        end)

      assert result == [{:c, []}, {:b, [:c]}, {:a, [:b, :c]}]
    end

    test "returns a halted tuple when called with a halt accumulator" do
      assert EnumUtils.reduce_peeking([1], {:halt, :done}, fn _head, _tail, accumulator ->
               {:cont, accumulator}
             end) == {:halted, :done}
    end

    test "returns a suspended tuple when called with a suspend accumulator" do
      assert {:suspended, :paused, continuation} =
               EnumUtils.reduce_peeking([1], {:suspend, :paused}, fn _head, _tail, accumulator ->
                 {:cont, accumulator}
               end)

      assert is_function(continuation, 1)
    end
  end

  describe "combine_list/1" do
    test "a single element list returns its string form" do
      assert EnumUtils.combine_list([:a]) == ["a"]
    end

    test "combines elements into progressive prefixes" do
      assert EnumUtils.combine_list([:a, :b, :c]) == ["a", "a_b", "a_b_c"]
    end

    test "works with string elements" do
      assert EnumUtils.combine_list(["x", "y"]) == ["x", "x_y"]
    end

    test "an empty list returns an empty list" do
      # Regression: combine_list([]) raised FunctionClauseError.
      assert EnumUtils.combine_list([]) == []
    end
  end
end
