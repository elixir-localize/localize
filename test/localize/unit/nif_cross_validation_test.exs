if Localize.Nif.available?() do
  defmodule Localize.Unit.NifCrossValidationTest do
    @moduledoc """
    Cross-validation tests comparing pure Elixir unit formatting
    with ICU's NumberFormatter unit formatting via the NIF.

    Skipped if the NIF is not available.
    """

    use ExUnit.Case, async: true
    use ExUnitProperties

    @moduletag :nif

    # ── Differential property test ──────────────────────────────
    #
    # Generates common unit / locale / style / number combinations,
    # formats each with both the pure-Elixir backend and ICU (via the
    # NIF), and asserts they are byte-identical. Scoped to units where
    # the pinned CLDR 48.2 data and the system ICU agree: base units
    # match exactly across every locale, as do precomposed compounds
    # and direct-pattern per-compounds. The only residual is data
    # spelling that skews between ICU's bundled CLDR and our pin — held
    # in @version_skew_quarantine — so this stays a stable gate rather
    # than a version tripwire. See memory `nif-uses-system-icu-version-skew`.
    @differential_locales ~w(en fr de es it pt ru ja nl pl ar zh)a
    @differential_styles [:long, :short]
    @differential_numbers [1, 5, 42]

    @differential_base_units ~w(
      meter kilometer centimeter millimeter mile foot inch yard
      kilogram gram milligram pound ounce tonne
      liter milliliter gallon
      second minute hour day week month year
      celsius fahrenheit kelvin
      watt kilowatt joule volt ampere newton
      hectare acre byte megabyte gigabyte
      year-person month-person week-person day-person
    )

    # Precomposed compounds + direct-pattern per-compounds, runtime-
    # composed per-compounds (denominator has no per_unit_pattern, so it
    # goes through the compound.per composition), and one runtime-composed
    # times-compound (tonne-kilometer) to exercise the grammatical
    # derivation — all match ICU exactly.
    @differential_compounds ~w(
      meter-per-second kilometer-per-hour mile-per-hour foot-per-second
      mile-per-gallon liter-per-100-kilometer gram-per-liter
      yard-per-millimeter gram-per-hour foot-per-minute
      kilometer-per-liter watt-per-kilogram
      newton-meter kilowatt-hour watt-hour tonne-kilometer
    )

    @differential_units @differential_base_units ++ @differential_compounds

    # {unit, locale} pairs that differ from ICU only by data-version
    # spelling, not algorithm — each verified by hand. All are the
    # composed "tonne-kilometer" times-compound:
    #   * es — "kilómetros" vs ICU "kilometros" (accent; CLDR 48.2 has no
    #     accent-less form, and simple + precomposed units match ICU).
    #   * ar — trailing plural-form selection differs under ICU 78.
    #   * zh — "公里" vs ICU "千米", both valid words for kilometer.
    # Shrinks when the pin and the system ICU realign.
    @version_skew_quarantine MapSet.new([
                               {"tonne-kilometer", :es},
                               {"tonne-kilometer", :ar},
                               {"tonne-kilometer", :zh}
                             ])

    describe "differential vs ICU (property)" do
      # Excluded by default: the @version_skew_quarantine is calibrated to
      # a specific system ICU (icu4c@78 ≈ CLDR 48). Run deliberately in a
      # known-ICU environment with `mix test --include nif_differential`.
      # The version-independent gate lives in formatter_property_test.exs.
      @tag :nif_differential
      property "common units and compounds format identically to ICU" do
        check all(
                unit_name <- member_of(@differential_units),
                locale <- member_of(@differential_locales),
                style <- member_of(@differential_styles),
                number <- member_of(@differential_numbers),
                max_runs: 2000
              ) do
          {:ok, unit} = Localize.Unit.new(number, unit_name)
          {:ok, elixir_result} = Localize.Unit.to_string(unit, locale: locale, format: style)

          {:ok, icu_result} =
            Localize.Nif.unit_format(number, unit_name, Atom.to_string(locale),
              style: Atom.to_string(style)
            )

          # Quarantined pairs diverge only by ICU/CLDR version skew
          # (documented above); still formatted on both sides, just not
          # asserted equal.
          unless MapSet.member?(@version_skew_quarantine, {unit_name, locale}) do
            assert elixir_result == icu_result,
                   "#{number} #{unit_name} (#{locale}/#{style}): " <>
                     "elixir=#{inspect(elixir_result)} icu=#{inspect(icu_result)}"
          end
        end
      end
    end

    @test_units [
      {"meter", :long},
      {"meter", :short},
      {"kilogram", :long},
      {"kilogram", :short},
      {"celsius", :short},
      {"mile-per-hour", :long},
      {"mile-per-hour", :short},
      {"liter", :long},
      {"liter", :short}
    ]

    @test_numbers [1, 42, 1000, 0]

    describe "unit formatting cross-validation (en)" do
      for {unit_name, style} <- @test_units do
        for number <- @test_numbers do
          test "en: #{number} #{unit_name} (#{style})" do
            unit_name = unquote(unit_name)
            style = unquote(style)
            number = unquote(number)

            {:ok, icu_result} =
              Localize.Nif.unit_format(number, unit_name, "en", style: Atom.to_string(style))

            {:ok, unit} = Localize.Unit.new(number, unit_name)

            {:ok, elixir_result} =
              Localize.Unit.to_string(unit, locale: :en, format: style)

            assert icu_result == elixir_result,
                   "ICU: #{inspect(icu_result)} vs Elixir: #{inspect(elixir_result)} " <>
                     "for #{number} #{unit_name} (#{style})"
          end
        end
      end
    end

    describe "unit formatting cross-validation (de)" do
      for number <- [1, 42] do
        test "de: #{number} meter (long)" do
          number = unquote(number)

          {:ok, icu_result} =
            Localize.Nif.unit_format(number, "meter", "de", style: "long")

          {:ok, unit} = Localize.Unit.new(number, "meter")
          {:ok, elixir_result} = Localize.Unit.to_string(unit, locale: :de, format: :long)

          assert icu_result == elixir_result,
                 "ICU: #{inspect(icu_result)} vs Elixir: #{inspect(elixir_result)}"
        end
      end
    end
  end
end
