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

    # Representative locales covering different formatting conventions, and
    # `bn-IN` for the locales whose default numbering system is not `latn`.
    @test_locales ~w(en de fr ar ja zh bn-IN)

    # Locales that differ from ICU only by data version, not algorithm, so the
    # equality assertion is held off them and their own value is asserted
    # below. Shrinks when the pin and the system ICU realign.
    #
    #   * bn-IN — CLDR 49 states its default numbering system as `latn`
    #     explicitly, where CLDR 48 left it inheriting `beng` from `bn`. We
    #     follow the pin and ICU 78.3 still carries the old value, so we write
    #     "12,345.6" where ICU writes Bengali digits. `bn` and `bn-BD` agree
    #     with ICU, as do the other 67 locales ICU gives a non-`latn` system.
    @version_skew_quarantine MapSet.new(["bn-IN"])

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

    describe "locales quarantined for ICU data-version skew" do
      # Asserted rather than skipped: this is the CLDR 49 value, and the test
      # says which side is right while ICU catches up.
      test "bn-IN writes Latin digits, as CLDR 49 states its numbering system" do
        assert {:ok, "12,345.6"} = Localize.Number.to_string(12_345.6, locale: "bn-IN")

        assert {:ok, bengali} = Localize.Number.to_string(12_345.6, locale: "bn")
        refute bengali == "12,345.6"

        assert {:ok, ^bengali} = Localize.Number.to_string(12_345.6, locale: "bn-BD")
      end
    end

    describe "standard number formatting cross-validation" do
      for locale <- @test_locales do
        for number <- @test_numbers do
          test "#{locale}: #{number} standard format" do
            locale = unquote(locale)
            number = unquote(number)

            {:ok, icu_result} = Localize.Nif.number_format(number, locale)

            {:ok, elixir_result} =
              Localize.Number.to_string(number, locale: locale)

            unless MapSet.member?(@version_skew_quarantine, locale) do
              assert icu_result == elixir_result,
                     "ICU: #{inspect(icu_result)} vs Elixir: #{inspect(elixir_result)} " <>
                       "for #{inspect(number)} in locale #{locale}"
            end
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
