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
      megajoule gigajoule nanogram kilobecquerel megabecquerel
      terawatt microsecond nanometer picofarad femtometer
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

    # {unit, locale} pairs where ICU writes a word the pinned CLDR data does
    # not have. CLDR wins, so each of these is settled rather than pending:
    # the pair is still formatted on both sides, just not asserted equal. Each
    # was read out of the CLDR XML against ICU 78.3 on 2026-10-08, and all are
    # the composed "tonne-kilometer" times-compound.
    #   * es — ours "kilómetro"/"kilómetros" is `es.xml`'s long unitPattern
    #     for length-kilometer; ICU drops the accent.
    #   * ar — ours "كيلومترات" is `ar.xml`'s `few` pattern, the right plural
    #     category for 5; ICU's "كيلوأمتار" is in no pattern of that unit.
    #   * zh — ours "公里" is the only kilometer name `zh.xml` carries,
    #     explicit at short and inherited by long and narrow; ICU writes
    #     "千米".
    # And one cause that is a compound pattern rather than a unit name, which
    # reaches every times-compound in that locale:
    #   * it at long — `it.xml` gives the `times` compound pattern as
    #     "{0} {1}", a space, explicitly at long, where ICU uses root's
    #     "{0}⋅{1}": ours are "watt ore" and "tonnellata metrica chilometri".
    #     Short and narrow do inherit the dotted form and agree.
    #
    # Swept exhaustively on 2026-10-08 — every unit × locale × style × number
    # the property draws from, 4,896 combinations — and these five pairs are
    # the whole of it, 19 cases. A sweep is the way to re-check this list,
    # because the property samples and will surface them one at a time.
    # Do not expect these to clear with a newer ICU. A pair that starts
    # agreeing, or a new disagreement, means the CLDR data moved: re-read the
    # XML before deciding which side is right, rather than assuming ICU.
    @version_skew_quarantine MapSet.new([
                               {"tonne-kilometer", :es},
                               {"tonne-kilometer", :ar},
                               {"tonne-kilometer", :zh},
                               {"tonne-kilometer", :it},
                               {"watt-hour", :it}
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
