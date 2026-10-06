defmodule Localize.DateTime.RelativeMatrixTest do
  @moduledoc """
  Relative times across locales, the three widths, every unit, both
  `:numeric` modes, both directions and each plural category the locales
  use, with values that exercise grouping, native digits, fractions and
  rounding.

  Expected values come from ICU4C 78.3's `RelativeDateTimeFormatter`, its
  number format grouping by CLDR's minimum grouping digits as ECMA-402 does
  (`test/support/data/relative_icu_expected.tsv`), except where CLDR 49 has
  changed the patterns since ICU's CLDR 48; those cases take the CLDR 49
  string (`test/support/data/relative_cldr49_changes.tsv`), and except
  where ICU names an offset that is no whole number, which TR35's
  `relative` does not; those are held to TR35 here. Every case goes
  through `to_string/2` and `to_parts/2`: the parts must join to the string,
  and the number's parts must be split as ICU splits them and carry the unit.

  """

  use ExUnit.Case, async: true

  alias Localize.DateTime.Relative

  @data Path.join([__DIR__, "..", "..", "support", "data"])
  @fixture Path.join(@data, "relative_icu_expected.tsv")
  @cldr_49_changes Path.join(@data, "relative_cldr49_changes.tsv")
  @formats %{"long" => :standard, "short" => :short, "narrow" => :narrow}

  # ICU formats these with root's arab symbols ("١٬٠٠٠٫٥"). Root defines
  # symbols for arab and arabext itself, but the CLDR JSON Localize is built
  # from carries a locale's symbols only for the numbering systems it uses,
  # so root's are not available to inherit.
  @root_symbol_locales ["en-u-nu-arab", "de-u-nu-arab"]

  test "relative times match ICU, or CLDR 49 where it changed the data" do
    changes = cldr_49_changes()
    named = named_by_tolerance(rows(@fixture))

    mismatches =
      for [locale, style, unit, numeric, value, icu, number, _category] <- rows(@fixture),
          locale not in @root_symbol_locales,
          not MapSet.member?(named, {locale, style, unit, numeric, value}),
          expected = expected_value(changes, {locale, style, unit, numeric, value}, icu),
          mismatch <- [check_case(locale, style, unit, numeric, value, expected, number)],
          mismatch != nil,
          do: mismatch

    assert mismatches == [], report(mismatches)
  end

  # TR35's `relative` is a name "for the current instance of the field, and
  # one or two past and future instances", "the day with relative value -1"
  # being "Yesterday": an instance is a whole number of the field away.
  # ICU4C names an offset within half a hundredth of a whole number too,
  # "tomorrow" for 0.9999 and for 1.004 days and "today" for 0.004. Those
  # rows of its fixture are known from the fixture alone, their string
  # being the name it gives the whole number beside them, and are held to
  # TR35: the offset is written as its number, which for 0.9999 is ICU's
  # own string with `numeric: always`.
  test "an offset that is no whole number is the number, where ICU names it" do
    fixture = rows(@fixture)
    named = named_by_tolerance(fixture)
    assert MapSet.size(named) == 276

    always =
      for [locale, style, unit, "always", value, icu | _rest] <- fixture,
          into: %{},
          do: {{locale, style, unit, value}, icu}

    for [locale, style, unit, numeric, value, icu | _rest] <- fixture,
        MapSet.member?(named, {locale, style, unit, numeric, value}),
        locale not in @root_symbol_locales do
      options = [
        unit: String.to_existing_atom(unit),
        format: Map.fetch!(@formats, style),
        locale: locale
      ]

      offset = parse_value(value)
      {:ok, written} = Relative.to_string(offset, [numeric: :auto] ++ options)

      assert written != icu, inspect({locale, style, unit, value})
      assert {:ok, written} == Relative.to_string(offset, [numeric: :always] ++ options)

      case Map.fetch(always, {locale, style, unit, value}) do
        {:ok, numbered} -> assert written == numbered, inspect({locale, style, unit, value})
        :error -> :ok
      end

      assert {:ok, parts} = Relative.to_parts(offset, [numeric: :auto] ++ options)
      assert Enum.map_join(parts, & &1.value) == written
    end
  end

  test "each CLDR 49 change replaces a case in the ICU fixture" do
    icu =
      Map.new(rows(@fixture), fn [l, s, u, n, v, expected | _] -> {{l, s, u, n, v}, expected} end)

    stale =
      for {key, {icu_48, _cldr_49}} <- cldr_49_changes(), Map.get(icu, key) != icu_48, do: key

    assert stale == []
  end

  describe "invalid input" do
    @values [
      nil,
      "",
      :"",
      "3 days",
      :bogus,
      %{},
      [],
      {1, 2},
      Decimal.new("1.5"),
      10 ** 30,
      1.0e300,
      -1.0e300,
      ~D[2024-01-01],
      ~T[10:00:00],
      ~N[2024-01-01 10:00:00],
      ~U[2024-01-01 10:00:00Z]
    ]

    @option_sets [
      [],
      [unit: :day],
      [unit: :mon, numeric: :always, format: :narrow],
      [unit: :bogus],
      [unit: "day"],
      [unit: :""],
      [format: :bogus],
      [format: nil],
      [numeric: :bogus],
      [numeric: nil],
      [locale: "zz-invalid!"],
      [locale: nil],
      [locale: :""],
      [locale: "ar-EG-u-nu-latn"],
      [relative_to: nil],
      [relative_to: "yesterday"],
      [relative_to: ~D[2024-01-02]],
      [relative_to: ~T[09:00:00]]
    ]

    test "never raises, and the parts join to the string" do
      failures =
        for value <- @values,
            options <- @option_sets,
            failure <- [invalid_input_failure(value, options)],
            failure != nil,
            do: {value, options, failure}

      assert failures == [], inspect(Enum.take(failures, 20), pretty: true, limit: 20)
    end
  end

  defp rows(path) do
    for line <- File.stream!(path),
        line = String.trim_trailing(line, "\n"),
        line != "" and not String.starts_with?(line, "#"),
        do: String.split(line, "\t")
  end

  defp cldr_49_changes do
    for [locale, style, unit, numeric, value, icu_48, cldr_49] <- rows(@cldr_49_changes),
        into: %{},
        do: {{locale, style, unit, numeric, value}, {icu_48, cldr_49}}
  end

  defp expected_value(changes, key, icu) do
    case Map.fetch(changes, key) do
      {:ok, {_icu_48, cldr_49}} -> cldr_49
      :error -> icu
    end
  end

  defp check_case(locale, style, unit, numeric, value, expected, number) do
    unit = String.to_existing_atom(unit)

    options = [
      unit: unit,
      format: Map.fetch!(@formats, style),
      numeric: String.to_existing_atom(numeric),
      locale: locale
    ]

    value = parse_value(value)
    string = Relative.to_string(value, options)
    parts = Relative.to_parts(value, options)
    key = {locale, style, unit, numeric, value}

    cond do
      string != {:ok, expected} ->
        {key, expected, string}

      not match?({:ok, _parts}, parts) ->
        {key, expected, {:parts, parts}}

      Enum.map_join(elem(parts, 1), & &1.value) != expected ->
        {key, expected, {:parts_do_not_join, parts}}

      number_parts(elem(parts, 1), unit) != number ->
        {key, number, {:number_parts, parts}}

      # ICU takes a double, so its 3 is also 3.0, which displays as "3".
      is_integer(value) and Relative.to_string(value * 1.0, options) != string ->
        {key, expected, {:float, Relative.to_string(value * 1.0, options)}}

      true ->
        nil
    end
  end

  # The rows in which ICU names an offset that is no whole number: with
  # `numeric: auto`, a value with a fraction whose string is the name ICU
  # gives the whole number nearest it, a name being a string that is not
  # that whole number's with `numeric: always`.
  defp named_by_tolerance(fixture) do
    strings =
      Map.new(fixture, fn [locale, style, unit, numeric, value, icu | _rest] ->
        {{locale, style, unit, numeric, value}, icu}
      end)

    for [locale, style, unit, "auto", value, icu | _rest] <- fixture,
        String.contains?(value, "."),
        whole = value |> String.to_float() |> round() |> Integer.to_string(),
        name = Map.get(strings, {locale, style, unit, "auto", whole}),
        name == icu,
        name != Map.get(strings, {locale, style, unit, "always", whole}),
        into: MapSet.new(),
        do: {locale, style, unit, "auto", value}
  end

  defp parse_value(value) do
    if String.contains?(value, "."), do: String.to_float(value), else: String.to_integer(value)
  end

  # The number's parts in the fixture's encoding, or a marker when a part
  # does not carry the unit.
  defp number_parts(parts, unit) do
    parts
    |> Enum.reject(&(&1.type == :literal))
    |> Enum.map_join(" ", fn
      %{type: type, value: value, unit: ^unit} -> "#{type}:#{value}"
      part -> "missing unit: #{inspect(part)}"
    end)
  end

  defp invalid_input_failure(value, options) do
    options = Keyword.put_new(options, :relative_to, ~U[2024-06-15 12:00:00Z])
    string = Relative.to_string(value, options)
    parts = Relative.to_parts(value, options)

    case {string, parts} do
      {{:ok, string}, {:ok, parts}} ->
        if Enum.map_join(parts, & &1.value) == string, do: nil, else: {:parts_do_not_join, parts}

      {{:error, %{__exception__: true} = error}, {:error, %{__exception__: true}}} ->
        # An error without a message raises here and fails the test.
        _message = Exception.message(error)
        nil

      other ->
        {:unexpected, other}
    end
  end

  defp report(mismatches) do
    lines =
      mismatches
      |> Enum.take(30)
      |> Enum.map_join("\n", fn {key, expected, actual} ->
        "  #{inspect(key)}: expected #{inspect(expected)}, " <>
          "got #{inspect(actual, printable_limit: 200, limit: 12)}"
      end)

    "#{length(mismatches)} mismatches\n#{lines}"
  end
end
