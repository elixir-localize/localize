defmodule Localize.List.PatternTest do
  use ExUnit.Case, async: true

  doctest Localize.List.Pattern

  alias Localize.List.Pattern

  describe "new/1" do
    test "creates pattern from template strings" do
      assert {:ok, %Pattern{}} =
               Pattern.new(
                 two: "{0} and {1}",
                 start: "{0}, {1}",
                 middle: "{0}, {1}",
                 end: "{0}, and {1}"
               )
    end

    test "creates pattern from pre-parsed token lists" do
      assert {:ok, %Pattern{two: [0, " and ", 1]}} =
               Pattern.new(
                 two: [0, " and ", 1],
                 start: [0, ", ", 1],
                 middle: [0, ", ", 1],
                 end: [0, ", and ", 1]
               )
    end

    test "returns error for missing key" do
      assert {:error, _exception} =
               Pattern.new(
                 two: "{0} and {1}",
                 start: "{0}, {1}",
                 middle: "{0}, {1}"
               )
    end
  end

  describe "from_locale_data/1" do
    test "normalizes integer key 2 to :two" do
      data = %{
        2 => [0, " and ", 1],
        start: [0, ", ", 1],
        middle: [0, ", ", 1],
        end: [0, ", and ", 1]
      }

      pattern = Pattern.from_locale_data(data)
      assert pattern.two == [0, " and ", 1]
      assert pattern.start == [0, ", ", 1]
    end
  end
end
