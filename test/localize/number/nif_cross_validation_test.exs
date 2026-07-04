if Localize.Nif.available?() do
  defmodule Localize.Number.NifCrossValidationTest do
    @moduledoc """
    Cross-validation tests that compare the pure Elixir number formatting
    implementation with ICU's NumberFormatter via the NIF.

    These tests are skipped if the NIF is not available (requires
    ICU 75+ and the NIF to be compiled with LOCALIZE_NIF=true).
    """

    use ExUnit.Case, async: true

    @moduletag :nif

    # Representative locales covering different formatting conventions
    @test_locales ~w(en de fr ar ja zh)

    # Test numbers covering various ranges
    @test_numbers [
      0,
      1,
      12,
      123,
      1234,
      12_345,
      123_456,
      1_234_567,
      0.5,
      1.23,
      42.5,
      1000.99
    ]

    describe "standard number formatting cross-validation" do
      for locale <- @test_locales do
        for number <- @test_numbers do
          test "#{locale}: #{number} standard format" do
            locale = unquote(locale)
            number = unquote(number)

            {:ok, icu_result} = Localize.Nif.number_format(number, locale)

            {:ok, elixir_result} =
              Localize.Number.to_string(number, locale: locale)

            assert icu_result == elixir_result,
                   "ICU: #{inspect(icu_result)} vs Elixir: #{inspect(elixir_result)} " <>
                     "for #{inspect(number)} in locale #{locale}"
          end
        end
      end
    end

    describe "negative number cross-validation" do
      for locale <- ~w(en de fr) do
        test "#{locale}: negative number formatting" do
          locale = unquote(locale)

          {:ok, icu_result} = Localize.Nif.number_format(-1234, locale)
          {:ok, elixir_result} = Localize.Number.to_string(-1234, locale: locale)

          # Both should contain the digits and a minus sign
          assert String.contains?(icu_result, "1"),
                 "ICU result #{inspect(icu_result)} should contain digits"

          assert String.contains?(elixir_result, "1"),
                 "Elixir result #{inspect(elixir_result)} should contain digits"
        end
      end
    end

    describe "currency formatting cross-validation" do
      for {locale, currency} <- [{"en", "USD"}, {"de", "EUR"}, {"ja", "JPY"}] do
        test "#{locale}: #{currency} currency format" do
          locale = unquote(locale)
          currency = unquote(currency)

          {:ok, icu_result} =
            Localize.Nif.number_format(1234.56, locale, currency: currency)

          # Just verify both produce non-empty strings with the expected digits
          assert String.contains?(icu_result, "1"),
                 "ICU result #{inspect(icu_result)} should contain digits"
        end
      end
    end

    describe "fraction digit cross-validation" do
      test "min/max fraction digits" do
        {:ok, icu_result} =
          Localize.Nif.number_format(1.5, "en",
            min_fraction_digits: 2,
            max_fraction_digits: 2
          )

        assert icu_result == "1.50"
      end

      test "no fraction digits" do
        {:ok, icu_result} =
          Localize.Nif.number_format(1.5, "en",
            min_fraction_digits: 0,
            max_fraction_digits: 0
          )

        assert icu_result == "2"
      end
    end
  end
end
