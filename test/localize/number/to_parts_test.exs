defmodule Localize.Number.ToPartsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # ECMA-402 `formatToParts`. Part shapes verified against
  # `Intl.NumberFormat.prototype.formatToParts`.

  defp concat(parts), do: Enum.map_join(parts, & &1.value)

  describe "to_parts/2 shapes" do
    test "decimal with grouping and sign" do
      assert {:ok,
              [
                %{type: :minus_sign, value: "-"},
                %{type: :integer, value: "1"},
                %{type: :group, value: ","},
                %{type: :integer, value: "234"},
                %{type: :decimal, value: "."},
                %{type: :fraction, value: "5"}
              ]} = Localize.Number.to_parts(-1234.5)
    end

    test "currency" do
      assert {:ok,
              [
                %{type: :currency, value: "$"},
                %{type: :integer, value: "1"},
                %{type: :group, value: ","},
                %{type: :integer, value: "234"},
                %{type: :decimal, value: "."},
                %{type: :fraction, value: "50"}
              ]} = Localize.Number.to_parts(1234.5, currency: :USD)
    end

    test "percent" do
      assert {:ok, [%{type: :integer, value: "46"}, %{type: :percent_sign, value: "%"}]} =
               Localize.Number.to_parts(0.456, format: :percent)
    end

    test "scientific exponent parts" do
      assert {:ok,
              [
                %{type: :integer, value: "1"},
                %{type: :decimal, value: "."},
                %{type: :fraction, value: "23456789"},
                %{type: :exponent_separator, value: "E"},
                %{type: :exponent_integer, value: "5"}
              ]} = Localize.Number.to_parts(123_456.789, format: :scientific)
    end

    test "compact formats tag the affix as :compact" do
      assert {:ok,
              [
                %{type: :integer, value: "1"},
                %{type: :decimal, value: "."},
                %{type: :fraction, value: "2"},
                %{type: :compact, value: "M"}
              ]} = Localize.Number.to_parts(1_234_567, format: :decimal_short)

      assert {:ok, parts} =
               Localize.Number.to_parts(1234, format: :currency_short, currency: :USD)

      assert %{type: :currency, value: "$"} = hd(parts)
      assert %{type: :compact, value: "K"} = List.last(parts)
    end

    test "digits transliterate per part" do
      assert {:ok,
              [
                %{type: :integer, value: "๑"},
                %{type: :group, value: ","},
                %{type: :integer, value: "๒๓๔"},
                %{type: :decimal, value: "."},
                %{type: :fraction, value: "๕"}
              ]} = Localize.Number.to_parts(1234.5, locale: "en-u-nu-thai")
    end

    test "an algorithmic numbering system is one integer part" do
      assert {:ok, [%{type: :integer, value: "一千二百三十四"}]} =
               Localize.Number.to_parts(1234, locale: :zh, number_system: :hans)
    end

    test "NaN and infinity" do
      assert {:ok, [%{type: :nan, value: "NaN"}]} = Localize.Number.to_parts(Decimal.new("NaN"))

      assert {:ok, [%{type: :infinity, value: "∞"}]} =
               Localize.Number.to_parts(Decimal.new("Infinity"))
    end

    test "sign display options flow through" do
      assert {:ok, [%{type: :plus_sign, value: "+"} | _]} =
               Localize.Number.to_parts(42, sign_display: :always)
    end

    test "unsupported formats return an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_parts(1234, format: :currency_long, currency: :USD)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_parts(1234, format: :spellout_cardinal)
    end

    test "to_parts!/2 raises on error" do
      assert_raise Localize.InvalidValueError, fn ->
        Localize.Number.to_parts!(1234, format: :currency_long, currency: :USD)
      end
    end
  end

  describe "to_parts/2 concatenation equals to_string/2" do
    test "across formats and locales" do
      cases = [
        {-1234.5, []},
        {1234.5, [currency: :USD]},
        {0.456, [format: :percent]},
        {123_456.789, [format: :scientific]},
        {1_234_567, [format: :decimal_short]},
        {1_234_567, [format: :decimal_long]},
        {1234, [format: :currency_short, currency: :USD]},
        {1234.5, [locale: "de", currency: :EUR]},
        {1234.5, [locale: "en-u-nu-thai"]},
        {-42, [locale: "fr", fractional_digits: 2]},
        {1000, [fractional_digits: 2, trailing_zero_display: :strip_if_integer]},
        {42, [minimum_integer_digits: 5]},
        {0, [sign_display: :always]}
      ]

      for {number, options} <- cases do
        {:ok, string} = Localize.Number.to_string(number, options)
        {:ok, parts} = Localize.Number.to_parts(number, options)

        assert concat(parts) == string,
               "parts #{inspect(parts)} != #{inspect(string)} for #{inspect(number)} #{inspect(options)}"
      end
    end

    property "random floats round-trip in en and de" do
      check all(
              float <- StreamData.float(min: -1.0e12, max: 1.0e12),
              locale <- StreamData.member_of([:en, :de, :fr]),
              max_runs: 50
            ) do
        {:ok, string} = Localize.Number.to_string(float, locale: locale)
        {:ok, parts} = Localize.Number.to_parts(float, locale: locale)
        assert concat(parts) == string
      end
    end
  end
end
