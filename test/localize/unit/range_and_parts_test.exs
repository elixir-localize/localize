defmodule Localize.Unit.RangeAndPartsTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.PluralRule.Range

  describe "Unit.to_range_string/3" do
    test "applies the unit pattern once to the numeric range" do
      assert {:ok, "2–5 kilometers"} =
               Localize.Unit.to_range_string(
                 Localize.Unit.new!(2, "kilometer"),
                 Localize.Unit.new!(5, "kilometer"),
                 locale: :en
               )
    end

    test "short format" do
      assert {:ok, "2–5 km"} =
               Localize.Unit.to_range_string(
                 Localize.Unit.new!(2, "kilometer"),
                 Localize.Unit.new!(5, "kilometer"),
                 locale: :en,
                 format: :short
               )
    end

    test "plural-range rules select the pattern category" do
      assert {:ok, "0–1 jour"} =
               Localize.Unit.to_range_string(
                 Localize.Unit.new!(0, "day"),
                 Localize.Unit.new!(1, "day"),
                 locale: :fr
               )

      assert {:ok, "1–2 jours"} =
               Localize.Unit.to_range_string(
                 Localize.Unit.new!(1, "day"),
                 Localize.Unit.new!(2, "day"),
                 locale: :fr
               )
    end

    test "mismatched units are an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Unit.to_range_string(
                 Localize.Unit.new!(2, "kilometer"),
                 Localize.Unit.new!(5, "mile"),
                 locale: :en
               )
    end
  end

  describe "Unit.to_parts/2" do
    test "number parts plus unit and literal segments" do
      assert {:ok,
              [
                %{type: :integer, value: "42"},
                %{type: :literal, value: " "},
                %{type: :unit, value: "meters"}
              ]} = Localize.Unit.to_parts(Localize.Unit.new!(42, "meter"), locale: :en)
    end

    test "narrow format has no literal spacing" do
      {:ok, parts} =
        Localize.Unit.to_parts(Localize.Unit.new!(42, "meter"), locale: :en, format: :narrow)

      assert Enum.map_join(parts, & &1.value) ==
               Localize.Unit.to_string!(Localize.Unit.new!(42, "meter"),
                 locale: :en,
                 format: :narrow
               )
    end

    test "parts concatenate to the formatted string" do
      unit = Localize.Unit.new!(1234.5, "kilometer")
      {:ok, parts} = Localize.Unit.to_parts(unit, locale: :de)
      {:ok, string} = Localize.Unit.to_string(unit, locale: :de)

      assert Enum.map_join(parts, & &1.value) == string
    end

    test "a compound unit without a direct pattern is an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Unit.to_parts(Localize.Unit.new!(2, "foot-per-second"), locale: :en)
    end
  end

  describe "PluralRule.Range" do
    test "language without plural-ranges data falls back to the end category" do
      assert {:ok, :other} = Localize.Number.PluralRule.Range.plural_rule(:one, :other, "tlh")
    end
  end
end
