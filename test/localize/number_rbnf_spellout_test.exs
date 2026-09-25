defmodule Localize.NumberRbnfSpelloutTest do
  @moduledoc """
  Numbers spelled out with CLDR's rule-based number formats.

  Expected values come from ICU4C 78.3's `RuleBasedNumberFormat` with the
  locale's spellout rules: the default spellout rule set for `:spellout`, and
  the `%spellout-ordinal`, `%spellout-numbering-year` and
  `%spellout-cardinal` rule sets for the named formats. They cover whole and
  negative numbers, fractions spelled digit by digit, and German's soft
  hyphens (U+00AD).

  """

  use ExUnit.Case, async: true

  @cases [
    {:en, :spellout, 1.5, "one point five"},
    {:en, :spellout, 21, "twenty-one"},
    {:en, :spellout, -3, "minus three"},
    {:en, :spellout, 1234.5, "one thousand two hundred thirty-four point five"},
    {:en, :spellout, 0.25, "zero point two five"},
    {:en, :spellout_ordinal, 21, "twenty-first"},
    {:en, :spellout_numbering_year, 1999, "nineteen ninety-nine"},
    {:en, :spellout_cardinal, 100_000.75, "one hundred thousand point seven five"},
    {:fr, :spellout, 71, "soixante-et-onze"},
    {:fr, :spellout, 1.5, "un virgule cinq"},
    {:de, :spellout, 1.5, "eins Komma fünf"},
    {:de, :spellout, 21, "ein­und­zwanzig"},
    {:es, :spellout, 21.5, "veintiuno coma cinco"}
  ]

  test "spellout rules match ICU" do
    for {locale, format, number, expected} <- @cases do
      assert {locale, format, number,
              Localize.Number.to_string(number, format: format, locale: locale)} ==
               {locale, format, number, {:ok, expected}}
    end
  end
end
