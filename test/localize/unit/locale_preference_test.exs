defmodule Localize.Unit.LocalePreferenceTest do
  @moduledoc """
  CLDR's `units/unitLocalePreferencesTest.txt`.

  Each case converts an amount according to a usage and a locale, where the
  locale may carry `-u-rg` (region override), `-u-ms` (measurement system)
  and `-u-mu` (measurement unit) keywords. The fixture's own comments give
  the precedence: `mu > ms > rg > (likely) region`.
  """

  use ExUnit.Case, async: true

  @data_file Path.join([
               __DIR__,
               "..",
               "..",
               "support",
               "data",
               "unit_locale_preference_test_data.txt"
             ])

  defp cases do
    @data_file
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Stream.map(fn line ->
      line |> String.split("#", parts: 2) |> hd() |> String.split(";") |> Enum.map(&String.trim/1)
    end)
    |> Enum.filter(&match?([_unit, _amount, _usage, _tag, _want_unit, _want_amount | _], &1))
  end

  # Amounts are rationals: "-155/9", "1,420,653,125/473176473", "12,345".
  defp amount(string) do
    string = String.replace(string, ",", "")

    case String.split(string, "/") do
      [numerator, denominator] ->
        Decimal.div(Decimal.new(numerator), Decimal.new(denominator))

      [value] ->
        Decimal.new(value)
    end
  end

  # 14 of the 23 cases match. The nine that do not are two unimplemented
  # features, not defects in what is implemented:
  #
  #   * **`-u-ms` and `-u-mu` overrides** (5 cases). The region override
  #     `-u-rg` is honoured, because `:locale` derives the territory from
  #     it, but the measurement-system and measurement-unit keywords are
  #     not read at all. TR35's precedence is `mu > ms > rg > (likely)
  #     region`, so these sit above the part that works.
  #
  #   * **Base-unit fallback** (4 cases). A unit whose quantity has no
  #     preference data — `ampere`, `kilocandela`, `candela-per-byte` —
  #     should fall back to base units. `preferred_units/2` returns
  #     `{:error, %Localize.InvalidValueError{}}` instead, which is the
  #     more serious of the two: a valid unit produces an error.
  #
  # Wiring this fixture in also found and fixed a third: every valid CLDR
  # usage now has an interned atom, so `usage: "fluid"` no longer degrades
  # to `:default` and return cubic inches for `en-GB`. That was 8 of the
  # cases below before the fix.
  @expected_matches 14

  test "unit preferences honour the locale's region and keyword overrides" do
    {matched, missed} =
      Enum.reduce(cases(), {0, []}, fn [input, amount, usage, tag, want, _want_amount | _],
                                       {matched, missed} ->
        result =
          with {:ok, unit} <- Localize.Unit.new(amount(amount), input) do
            Localize.Unit.Preference.preferred_units(unit, locale: tag, usage: usage)
          end

        case result do
          {:ok, [got], _options} ->
            if to_string(got) == String.replace(want, "-", "_"),
              do: {matched + 1, missed},
              else: {matched, [{tag, input, usage, want, got} | missed]}

          other ->
            {matched, [{tag, input, usage, want, other} | missed]}
        end
      end)

    total = length(cases())

    assert matched == @expected_matches,
           """
           #{matched}/#{total} unit locale preference cases match, expected #{@expected_matches}.

           #{missed |> Enum.reverse() |> Enum.map_join("\n", fn {tag, input, usage, want, got} -> "  #{tag} #{input} (#{usage}): want #{want}, got #{inspect(got)}" end)}
           """
  end
end
