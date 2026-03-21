if Localize.Nif.available?() do
  defmodule Localize.Unit.NifCrossValidationTest do
    @moduledoc """
    Cross-validation tests comparing pure Elixir unit formatting
    with ICU's NumberFormatter unit formatting via the NIF.

    Skipped if the NIF is not available.
    """

    use ExUnit.Case, async: true

    @moduletag :nif

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
              Localize.Unit.to_string(unit, locale: :en, style: style)

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
          {:ok, elixir_result} = Localize.Unit.to_string(unit, locale: :de, style: :long)

          assert icu_result == elixir_result,
                 "ICU: #{inspect(icu_result)} vs Elixir: #{inspect(elixir_result)}"
        end
      end
    end
  end
end
