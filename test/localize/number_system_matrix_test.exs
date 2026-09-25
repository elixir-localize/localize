defmodule Localize.Number.SystemMatrixTest do
  @moduledoc """
  Numbers formatted in a numbering system other than the locale's default,
  through a `-u-nu-` locale and through the `:number_system` option: every
  system a locale has symbols for, and systems it inherits from root, in the
  decimal, percent and scientific formats.

  Expected values come from ICU4C 78.3's `NumberFormat`, grouping by CLDR's
  minimum grouping digits as ECMA-402 does
  (`test/support/data/number_system_icu_expected.tsv`). ICU 78.3 carries
  CLDR 48, the data Localize ships.

  """

  use ExUnit.Case, async: true

  @fixture Path.join([__DIR__, "..", "support", "data", "number_system_icu_expected.tsv"])
  @formats %{"decimal" => :standard, "percent" => :percent, "scientific" => :scientific}

  fixture_cases =
    for line <- File.stream!(@fixture),
        line = String.trim_trailing(line, "\n"),
        line != "" and not String.starts_with?(line, "#"),
        [_tag, _style, _value, _expected] = fixture_case <- [String.split(line, "\t")],
        do: fixture_case

  # One test per locale, so each loads only the locale it checks. A single
  # test over the whole fixture loaded 126 locales and, where they had to be
  # downloaded as in CI, ran past the test timeout.
  for {locale, cases} <-
        Enum.group_by(fixture_cases, fn [tag | _] -> hd(String.split(tag, "-u-nu-")) end) do
    test "#{locale} numbers in another numbering system match ICU" do
      mismatches =
        for [tag, style, value, expected] <- unquote(Macro.escape(cases)),
            mismatch <- [check_case(tag, style, value, expected)],
            mismatch != nil,
            do: mismatch

      assert mismatches == [], report(mismatches)
    end
  end

  defp check_case(tag, style, value, expected) do
    [base, system] = String.split(tag, "-u-nu-")

    number =
      if String.contains?(value, "."), do: String.to_float(value), else: String.to_integer(value)

    format = Map.fetch!(@formats, style)

    via_locale = Localize.Number.to_string(number, locale: tag, format: format)

    via_option =
      Localize.Number.to_string(number,
        locale: base,
        number_system: String.to_existing_atom(system),
        format: format
      )

    parts = Localize.Number.to_parts(number, locale: tag, format: format)

    cond do
      via_locale != {:ok, expected} ->
        {tag, style, value, expected, {:locale, via_locale}}

      via_option != {:ok, expected} ->
        {tag, style, value, expected, {:number_system, via_option}}

      not match?({:ok, _parts}, parts) or Enum.map_join(elem(parts, 1), & &1.value) != expected ->
        {tag, style, value, expected, {:parts, parts}}

      true ->
        nil
    end
  end

  defp report(mismatches) do
    lines =
      mismatches
      |> Enum.take(30)
      |> Enum.map_join("\n", fn {tag, style, value, expected, actual} ->
        "  #{tag} #{style} #{value}: expected #{inspect(expected)}, got #{inspect(actual)}"
      end)

    "#{length(mismatches)} mismatches\n#{lines}"
  end
end
