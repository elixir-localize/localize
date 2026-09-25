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

  # All 23 cases match. Getting there took three fixes, each found by this
  # fixture:
  #
  #   * Every usage CLDR defines now has an interned atom. The preference
  #     data is keyed by usage *string*, so nothing created them, and
  #     `String.to_existing_atom/1` failed for any usage no other module
  #     mentioned — `usage: "fluid"` silently became `:default` and
  #     returned cubic inches for `en-GB`.
  #
  #   * `-u-ms` and `-u-mu` are read. A measurement system stands for a
  #     territory that uses it; a measurement unit overrides the result
  #     outright, and is ignored when it is not convertible from the input.
  #
  #   * A unit whose quantity has no preferences falls back to base units
  #     rather than returning an error.
  @expected_matches 23

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
            # A preference unit comes back as an atom with underscores; a
            # derived compound base unit comes back as the CLDR identifier.
            if to_string(got) |> String.replace("_", "-") == want,
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
