defmodule Localize.Unit.FormatterPropertyTest do
  @moduledoc """
  Version-independent property tests for `Localize.Unit` formatting.

  CLDR ships conformance vectors for unit *conversion* and *preferences*
  but none for *formatting* or *parsing*, which is the gap that let the
  compound-unit issues (#42, #43) reach 1.0-rc.4. These properties assert
  invariants that hold regardless of CLDR data version, so they gate CI
  without depending on the ICU NIF. The exact-output comparison against
  ICU lives in `nif_cross_validation_test.exs` (tagged `:nif`).

  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Localize.Unit

  # The full set of CLDR base units (155 across 39 categories), computed
  # once at compile time.
  @base_units Unit.known_units_by_category() |> Map.values() |> List.flatten() |> Enum.sort()

  # Locales spanning distinct plural systems, scripts, and the one CLDR
  # locale that overrides the "times" grammatical derivation (fr).
  @locales [:en, :fr, :de, :es, :it, :pt, :ru, :ja, :nl, :pl, :ar, :zh]

  @styles [:long, :short, :narrow]

  # Units that format identically to a different unit cannot round-trip
  # through `parse` — the formatted string is genuinely ambiguous, not a
  # bug. `foodcalorie` formats to "Calories" (→ `calorie`); the
  # `-person` duration units format as their base unit ("month-person" →
  # "months" → `month`), matching ICU.
  @round_trip_excluded ~w(foodcalorie year-person month-person week-person day-person)

  # ── Generators ──────────────────────────────────────────────

  defp base_unit_gen, do: member_of(@base_units)

  # A "times" product of two distinct base units ("tonne-kilometer").
  defp times_unit_gen do
    gen all(a <- base_unit_gen(), b <- base_unit_gen(), a != b) do
      "#{a}-#{b}"
    end
  end

  # A "per" compound of two distinct base units ("gram-per-hour").
  defp per_unit_gen do
    gen all(a <- base_unit_gen(), b <- base_unit_gen(), a != b) do
      "#{a}-per-#{b}"
    end
  end

  # Biased toward compounds — the axis CLDR fixtures leave uncovered.
  defp unit_gen do
    one_of([base_unit_gen(), times_unit_gen(), times_unit_gen(), per_unit_gen(), per_unit_gen()])
  end

  defp locale_gen, do: member_of(@locales)
  defp style_gen, do: member_of(@styles)

  defp number_gen do
    one_of([
      member_of([0, 1, 2, 5, 21, 42, 100, 1000]),
      map(integer(2..9999), &(&1 / 4))
    ])
  end

  # ── Properties ──────────────────────────────────────────────

  property "every unit/locale/style/number formats to {:ok, string} without raising" do
    check all(
            unit_name <- unit_gen(),
            locale <- locale_gen(),
            style <- style_gen(),
            number <- number_gen(),
            max_runs: 1000
          ) do
      with {:ok, unit} <- Unit.new(number, unit_name) do
        result = Unit.to_string(unit, locale: locale, format: style)

        assert match?({:ok, formatted} when is_binary(formatted), result),
               "#{inspect(number)} #{unit_name} (#{locale}/#{style}) => #{inspect(result)}"
      end
    end
  end

  property "the localized number appears in the formatted output (base units)" do
    # Base units only, numbers >= 3. Two soundness constraints:
    #   * Small counts can be numberless: Arabic renders "2 hours" as the
    #     dual "ساعتان" with no digit. 3+ lands in a numeral-bearing
    #     plural category everywhere.
    #   * Compounds can legitimately drop the number when a component
    #     resolves to a numberless plural form (Arabic "rod-light-year"
    #     omits it — and ICU does the same), so the invariant only holds
    #     for simple units. Compound number placement is checked exactly
    #     against ICU in nif_cross_validation_test.exs.
    check all(
            unit_name <- base_unit_gen(),
            locale <- locale_gen(),
            number <- member_of([5, 42, 1000]),
            max_runs: 600
          ) do
      with {:ok, unit} <- Unit.new(number, unit_name),
           {:ok, formatted} <- Unit.to_string(unit, locale: locale),
           {:ok, localized_number} <- Localize.Number.to_string(number, locale: locale) do
        assert String.contains?(formatted, localized_number),
               "#{number} #{unit_name} (#{locale}) => #{inspect(formatted)} " <>
                 "is missing the localized number #{inspect(localized_number)}"
      end
    end
  end

  property "formatted base-unit names parse back to the same canonical unit (en)" do
    parseable = Enum.reject(@base_units, &(&1 in @round_trip_excluded))

    check all(
            unit_name <- member_of(parseable),
            number <- member_of([2, 5, 42]),
            max_runs: 400
          ) do
      {:ok, unit} = Unit.new(number, unit_name)
      {:ok, formatted} = Unit.to_string(unit, locale: :en)
      {:ok, reparsed} = Unit.parse(formatted, locale: :en)

      assert reparsed.name == unit_name,
             "#{inspect(formatted)} re-parsed to #{inspect(reparsed.name)}, expected #{unit_name}"
    end
  end
end
