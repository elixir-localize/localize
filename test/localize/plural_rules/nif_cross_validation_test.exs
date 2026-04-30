defmodule Localize.Number.PluralRule.NifCrossValidationTest do
  @moduledoc """
  Cross-validation tests that compare the pure Elixir plural rule
  implementation with ICU's PluralRules via the NIF.

  These tests are skipped if the NIF is not available (requires
  ICU 75+ and the NIF to be compiled with LOCALIZE_NIF=true).
  """

  use ExUnit.Case, async: true

  @moduletag :nif

  # Aliased outside the `if` block so the compiler does not warn when
  # the NIF is unavailable and the conditional body is compiled away.
  alias Localize.Number.PluralRule, warn: false

  if Localize.Nif.available?() do
    # Representative locales covering different plural rule categories
    @test_locales ~w(en fr ar de ja ru zh pl cs he cy uk ga)

    # Test numbers covering various operand combinations
    @test_integers [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      30,
      40,
      50,
      60,
      70,
      80,
      90,
      100,
      101,
      102,
      103,
      200,
      1000,
      1_000_000
    ]

    for locale <- @test_locales,
        number <- @test_integers do
      test "cardinal: Elixir and ICU agree for #{number} in #{locale}" do
        locale = unquote(locale)
        number = unquote(number)

        elixir_result = PluralRule.plural_type(number, locale: locale, type: :cardinal)
        {:ok, icu_result} = Localize.Nif.plural_rule(number, locale, :cardinal)

        assert elixir_result == icu_result,
               "Mismatch for cardinal #{number} in #{locale}: " <>
                 "Elixir=#{inspect(elixir_result)}, ICU=#{inspect(icu_result)}"
      end
    end

    for locale <- @test_locales,
        number <- @test_integers do
      test "ordinal: Elixir and ICU agree for #{number} in #{locale}" do
        locale = unquote(locale)
        number = unquote(number)

        elixir_result = PluralRule.plural_type(number, locale: locale, type: :ordinal)
        {:ok, icu_result} = Localize.Nif.plural_rule(number, locale, :ordinal)

        assert elixir_result == icu_result,
               "Mismatch for ordinal #{number} in #{locale}: " <>
                 "Elixir=#{inspect(elixir_result)}, ICU=#{inspect(icu_result)}"
      end
    end
  else
    @tag :skip
    test "NIF not available — skipping cross-validation tests" do
      IO.puts("\nSkipping NIF cross-validation: NIF not loaded")
      IO.puts("Build with LOCALIZE_NIF=true to enable these tests")
    end
  end
end
