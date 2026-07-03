defmodule Localize.Number.CompactPluralTest do
  use ExUnit.Case, async: true

  alias Localize.Number.PluralRule.Cardinal

  # Expected values verified against ICU via Intl.NumberFormat
  # (notation: :compact). Per TR35 (Compact Number Formats, step 8)
  # the plural category is selected from the mantissa as it will be
  # displayed; selecting on the unrounded mantissa while rendering the
  # rounded one produced grammatically impossible output such as
  # es "1 millones".
  describe "compact plural selection matches ICU" do
    @icu_reference [
      {:fr, 1_000_000, :decimal_long, "1 million"},
      {:fr, 1_200_000, :decimal_long, "1,2 million"},
      {:fr, 2_000_000, :decimal_long, "2 millions"},
      {:es, 1_000_000, :decimal_long, "1 millón"},
      {:es, 1_200_000, :decimal_long, "1,2 millones"},
      {:es, 2_000_000, :decimal_long, "2 millones"},
      {:it, 1_000_000, :decimal_long, "1 milione"},
      {:it, 1_200_000, :decimal_long, "1,2 milioni"},
      {:en, 1_000_000, :decimal_long, "1 million"},
      {:en, 1_200_000, :decimal_long, "1.2 million"},
      {:en, 1_200_000, :decimal_short, "1.2M"}
    ]

    for {locale, number, format, expected} <- @icu_reference do
      test "#{locale} #{number} #{format} renders #{expected}" do
        assert {:ok, unquote(expected)} =
                 Localize.Number.to_string(unquote(number),
                   format: unquote(format),
                   locale: unquote(locale)
                 )
      end
    end
  end

  describe "the exact-match count-1 compact pattern" do
    test "is selected when the rounded mantissa is exactly one" do
      # French has a count-"1" pattern ("mille") at 1000; 1001 rounds
      # to a mantissa of exactly 1 and must select it, matching ICU.
      assert {:ok, "mille"} =
               Localize.Number.to_string(1_000, format: :decimal_long, locale: :fr)

      assert {:ok, "mille"} =
               Localize.Number.to_string(1_001, format: :decimal_long, locale: :fr)

      assert {:ok, "1,1 millier"} =
               Localize.Number.to_string(1_100, format: :decimal_long, locale: :fr)
    end
  end

  # TR35 Plural Operand Examples table: the n, i, f, t, v and w
  # operands of a compact value are computed after shifting the
  # decimal point by the exponent; the exponent is the e operand.
  describe "compact {mantissa, exponent} plural operands" do
    setup do
      {:ok, fr} = Localize.validate_locale(:fr)
      %{fr: fr}
    end

    test "1.2c6 has the operands of 1200000 with e = 6", %{fr: fr} do
      # fr: e outside 0..5 selects :many; the same digits with e = 0
      # (plain 1200000) select :other.
      assert Cardinal.plural_rule({1.2, 6}, fr) == :many
      assert Cardinal.plural_rule(1_200_000, fr) == :other
    end

    test "1c6 selects :many in fr per the CLDR samples", %{fr: fr} do
      assert Cardinal.plural_rule({1, 6}, fr) == :many
      assert Cardinal.plural_rule({Decimal.new("1.2"), 6}, fr) == :many
    end

    test "integral shifted values behave like their integer equivalents", %{fr: fr} do
      # 1c6 = 1000000: the first :many disjunct (i % 1000000 = 0)
      # applies to the plain integer too.
      assert Cardinal.plural_rule(1_000_000, fr) == :many
      assert Cardinal.plural_rule(%Decimal{coef: 1, exp: 6, sign: 1}, fr) == :many
    end
  end
end
