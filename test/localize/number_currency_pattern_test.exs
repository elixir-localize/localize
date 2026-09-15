defmodule Localize.NumberCurrencyPatternTest do
  @moduledoc """
  Currency sign widths, currency spacing and the currency's decimal places
  in number patterns, through `Localize.Number.to_string/2`, its `:wrapper`
  option and `Localize.Number.to_parts/2`.

  Expected strings and parts come from ICU4C 78.3's `DecimalFormat` with the
  currency set, in five locales, five currencies with zero, two and three
  decimal places, eleven patterns and five values. Each part is checked
  against the field span ICU reports for its characters, and characters in
  no span are literals. ICU renders the narrow symbol width ¤¤¤¤¤ as U+FFFD,
  so those symbols come from TR35's pattern character table with CLDR 49's
  `alt="narrow"` symbols; the Swiss franc's are newer than ICU's CLDR 48
  data. TR35's handling of invalid patterns gives U+FFFD for four and six
  currency signs, as ICU does. Decimal places set through the API come from
  ECMA-402's `Intl.NumberFormat` in Node 24.

  """

  use ExUnit.Case, async: true

  @fixture Path.expand("../support/data/currency_pattern_icu_expected.tsv", __DIR__)
  @external_resource @fixture

  @rows @fixture
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.map(&String.split(&1, "\t"))

  @field_types %{
    "integer" => :integer,
    "group" => :group,
    "decimal" => :decimal,
    "fraction" => :fraction,
    "currency" => :currency,
    "sign" => :minus_sign
  }

  test "the fixture has every locale, currency, pattern and value" do
    assert length(@rows) == 5 * 5 * 11 * 5
  end

  test "strings, wrapped strings and parts match ICU" do
    wrapper = fn string, tag -> "<#{tag}>" <> string <> "</#{tag}>" end

    for [locale, pattern, value, code, expected | spans] <- @rows do
      expected = unescape(expected)
      label = {locale, pattern, value, code}
      number = to_number(value)

      options = [
        format: pattern,
        currency: String.to_existing_atom(code),
        locale: String.to_existing_atom(locale)
      ]

      assert {label, Localize.Number.to_string(number, options)} == {label, {:ok, expected}}

      assert {:ok, wrapped} =
               Localize.Number.to_string(number, Keyword.put(options, :wrapper, wrapper))

      assert {label, String.replace(wrapped, ~r/<\/?[a-z_]+>/, "")} == {label, expected}

      assert {:ok, parts} = Localize.Number.to_parts(number, options)

      assert {label, join_runs(Enum.map(parts, &{&1.type, &1.value}))} ==
               {label, icu_parts(expected, spans)}
    end
  end

  test "five currency signs are the narrow symbol" do
    for {locale, currency, expected} <- [
          {:en, :USD, "$1,234.56"},
          {:en, :AUD, "$1,234.56"},
          {:en, :EUR, "€1,234.56"},
          {:en, :JPY, "¥1,235"},
          {:ja, :JPY, "￥1,235"},
          {:en, :CHF, "Fr. 1,234.56"},
          {:fr, :CHF, "fr. 1 234,56"}
        ] do
      options = [format: "¤¤¤¤¤#,##0.00", currency: currency, locale: locale]

      assert {locale, currency, Localize.Number.to_string(1234.56, options)} ==
               {locale, currency, {:ok, expected}}
    end
  end

  test "four and six currency signs are invalid widths that format as U+FFFD" do
    for pattern <- ["¤¤¤¤#,##0.00", "¤¤¤¤¤¤#,##0.00"] do
      assert Localize.Number.to_string(1234.56, format: pattern, currency: :USD, locale: :en) ==
               {:ok, "�1,234.56"}
    end
  end

  test "decimal places set through the API override the currency's" do
    assert Localize.Number.to_string(1234.5678,
             format: "¤#,##0.00",
             currency: :USD,
             locale: :en,
             fractional_digits: 3
           ) == {:ok, "$1,234.568"}

    assert Localize.Number.to_string(1234.5678,
             format: "¤#,##0.00",
             currency: :JPY,
             locale: :en,
             fractional_digits: 2
           ) == {:ok, "¥1,234.57"}
  end

  test "a pattern with significant digits keeps them" do
    assert Localize.Number.to_string(1234.56, format: "@@@ ¤", currency: :USD, locale: :en) ==
             {:ok, "1230 $"}
  end

  defp to_number(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> String.to_float(value)
    end
  end

  defp unescape(string) do
    Regex.replace(~r/\\u\{([0-9a-f]+)\}/, string, fn _match, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  # Types each character by the innermost ICU field span covering it, so a
  # grouping separator inside an integer span is a group. The offsets are
  # UTF-16 code units, which match character indexes here because every
  # character in the fixture is in the Basic Multilingual Plane.
  defp icu_parts(expected, spans) do
    spans = Enum.map(spans, &parse_span/1)

    expected
    |> String.codepoints()
    |> Enum.with_index()
    |> Enum.map(fn {character, index} -> {character_type(index, spans), character} end)
    |> join_runs()
  end

  defp parse_span(span) do
    [_match, name, first, last] = Regex.run(~r/^(\w+)\[(\d+),(\d+)\)=/, span)
    {name, String.to_integer(first), String.to_integer(last)}
  end

  defp character_type(index, spans) do
    covering = for {name, first, last} <- spans, index >= first and index < last, do: name

    cond do
      covering == [] -> :literal
      "group" in covering -> :group
      true -> Map.fetch!(@field_types, hd(covering))
    end
  end

  defp join_runs(parts) do
    parts
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{type, _value} | _rest] = run -> {type, Enum.map_join(run, &elem(&1, 1))} end)
  end
end
