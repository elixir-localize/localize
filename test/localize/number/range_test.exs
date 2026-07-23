defmodule Localize.Number.RangeTest do
  use ExUnit.Case, async: true

  describe "to_range_string/3" do
    test "formats a basic range in English" do
      assert {:ok, "3" <> _} = Localize.Number.to_range_string(3, 5, locale: :en)
      {:ok, result} = Localize.Number.to_range_string(3, 5, locale: :en)
      assert result =~ "3"
      assert result =~ "5"
    end

    test "formats a range with grouping" do
      {:ok, result} = Localize.Number.to_range_string(1000, 5000, locale: :en)
      assert result =~ "1,000"
      assert result =~ "5,000"
    end

    test "uses approximately pattern when start equals end" do
      {:ok, result} = Localize.Number.to_range_string(5, 5, locale: :en)
      assert result == "~5"
    end

    test "uses approximately pattern with :approximate option" do
      # Regression: the range end used to be silently dropped,
      # producing "~3". The approximately pattern now wraps the
      # formatted range instead.
      {:ok, result} = Localize.Number.to_range_string(3, 5, locale: :en, approximate: true)
      assert result == "~3–5"
    end

    test ":approximate with equal start and end formats a single number" do
      {:ok, result} = Localize.Number.to_range_string(5, 5, locale: :en, approximate: true)
      assert result == "~5"
    end

    test "formats range in Japanese" do
      {:ok, result} = Localize.Number.to_range_string(3, 5, locale: :ja)
      assert result =~ "3"
      assert result =~ "5"
      # Japanese uses fullwidth tilde U+FF5E
      assert String.contains?(result, "\uFF5E")
    end

    test "formats range in German" do
      {:ok, result} = Localize.Number.to_range_string(1000, 5000, locale: :de)
      # German uses . for grouping
      assert result =~ "1.000"
      assert result =~ "5.000"
    end

    test "accepts an Elixir Range" do
      assert Localize.Number.to_range_string(3..5, locale: :en) ==
               Localize.Number.to_range_string(3, 5, locale: :en)
    end

    test "accepts a single-element Range" do
      {:ok, result} = Localize.Number.to_range_string(5..5, locale: :en)
      assert result == "~5"
    end
  end

  describe "to_range_string!/3" do
    test "returns string directly" do
      result = Localize.Number.to_range_string!(3, 5, locale: :en)
      assert is_binary(result)
      assert result =~ "3"
      assert result =~ "5"
    end

    test "accepts an Elixir Range" do
      assert Localize.Number.to_range_string!(3..5, locale: :en) ==
               Localize.Number.to_range_string!(3, 5, locale: :en)
    end
  end

  describe "to_at_least_string/2" do
    test "formats at-least in English" do
      assert {:ok, "5+"} = Localize.Number.to_at_least_string(5, locale: :en)
    end

    test "formats at-least with grouping" do
      {:ok, result} = Localize.Number.to_at_least_string(1000, locale: :en)
      assert result == "1,000+"
    end
  end

  describe "to_at_most_string/2" do
    test "formats at-most in English" do
      {:ok, result} = Localize.Number.to_at_most_string(5, locale: :en)
      assert result == "\u22645"
    end

    test "formats at-most with grouping" do
      {:ok, result} = Localize.Number.to_at_most_string(1000, locale: :en)
      assert result == "\u22641,000"
    end
  end

  describe "to_approximately_string/2" do
    test "formats approximately in English" do
      assert {:ok, "~5"} = Localize.Number.to_approximately_string(5, locale: :en)
    end

    test "formats approximately with grouping" do
      {:ok, result} = Localize.Number.to_approximately_string(1000, locale: :en)
      assert result == "~1,000"
    end
  end

  describe "to_range_parts/3" do
    test "tags start, shared, and end sources" do
      assert {:ok,
              [
                %{type: :integer, value: "3", source: :start_range},
                %{type: :literal, value: "–", source: :shared},
                %{type: :integer, value: "5", source: :end_range}
              ]} = Localize.Number.to_range_parts(3, 5, locale: :en)
    end

    test "equal endpoints use the approximately pattern with shared source" do
      assert {:ok,
              [
                %{type: :approximately_sign, value: "~", source: :shared},
                %{type: :integer, value: "5", source: :shared}
              ]} = Localize.Number.to_range_parts(5, 5, locale: :en)
    end

    test "approximate wraps the full range" do
      assert {:ok,
              [
                %{type: :approximately_sign, value: "~", source: :shared},
                %{type: :integer, value: "3", source: :start_range},
                %{type: :literal, value: "–", source: :shared},
                %{type: :integer, value: "5", source: :end_range}
              ]} = Localize.Number.to_range_parts(3, 5, locale: :en, approximate: true)
    end

    test "parts concatenate to the range string" do
      {:ok, parts} = Localize.Number.to_range_parts(100, 200, locale: :en, currency: :USD)
      {:ok, string} = Localize.Number.to_range_string(100, 200, locale: :en, currency: :USD)

      assert Enum.map_join(parts, & &1.value) == string
    end

    test "formats that do not decompose return an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_range_parts(1, 2, locale: :en, format: :spellout)
    end
  end
end
