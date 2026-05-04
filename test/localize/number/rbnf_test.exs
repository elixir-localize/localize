defmodule Localize.Number.RbnfTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.Rbnf

  alias Localize.Number.Rbnf

  describe "spellout cardinal (English)" do
    test "zero" do
      assert {:ok, "zero"} = Rbnf.to_string(0, :spellout_cardinal, locale: :en)
    end

    test "single digits" do
      assert {:ok, "one"} = Rbnf.to_string(1, :spellout_cardinal, locale: :en)
      assert {:ok, "five"} = Rbnf.to_string(5, :spellout_cardinal, locale: :en)
      assert {:ok, "nine"} = Rbnf.to_string(9, :spellout_cardinal, locale: :en)
    end

    test "teens" do
      assert {:ok, "ten"} = Rbnf.to_string(10, :spellout_cardinal, locale: :en)
      assert {:ok, "thirteen"} = Rbnf.to_string(13, :spellout_cardinal, locale: :en)
      assert {:ok, "nineteen"} = Rbnf.to_string(19, :spellout_cardinal, locale: :en)
    end

    test "tens" do
      assert {:ok, "twenty"} = Rbnf.to_string(20, :spellout_cardinal, locale: :en)
      assert {:ok, "twenty-one"} = Rbnf.to_string(21, :spellout_cardinal, locale: :en)
      assert {:ok, "ninety-nine"} = Rbnf.to_string(99, :spellout_cardinal, locale: :en)
    end

    test "hundreds" do
      assert {:ok, "one hundred"} = Rbnf.to_string(100, :spellout_cardinal, locale: :en)

      assert {:ok, "one hundred twenty-three"} =
               Rbnf.to_string(123, :spellout_cardinal, locale: :en)

      assert {:ok, "nine hundred ninety-nine"} =
               Rbnf.to_string(999, :spellout_cardinal, locale: :en)
    end

    test "thousands" do
      assert {:ok, "one thousand"} = Rbnf.to_string(1000, :spellout_cardinal, locale: :en)

      assert {:ok, "twelve thousand three hundred forty-five"} =
               Rbnf.to_string(12345, :spellout_cardinal, locale: :en)
    end

    test "millions" do
      assert {:ok, "one million"} = Rbnf.to_string(1_000_000, :spellout_cardinal, locale: :en)
    end

    test "negative numbers" do
      {:ok, result} = Rbnf.to_string(-42, :spellout_cardinal, locale: :en)
      assert String.contains?(result, "forty-two")
    end
  end

  describe "digits ordinal (English)" do
    test "1st through 4th" do
      assert {:ok, "1st"} = Rbnf.to_string(1, :digits_ordinal, locale: :en)
      assert {:ok, "2nd"} = Rbnf.to_string(2, :digits_ordinal, locale: :en)
      assert {:ok, "3rd"} = Rbnf.to_string(3, :digits_ordinal, locale: :en)
      assert {:ok, "4th"} = Rbnf.to_string(4, :digits_ordinal, locale: :en)
    end

    test "teens" do
      assert {:ok, "11th"} = Rbnf.to_string(11, :digits_ordinal, locale: :en)
      assert {:ok, "12th"} = Rbnf.to_string(12, :digits_ordinal, locale: :en)
      assert {:ok, "13th"} = Rbnf.to_string(13, :digits_ordinal, locale: :en)
    end

    test "larger numbers" do
      assert {:ok, "21st"} = Rbnf.to_string(21, :digits_ordinal, locale: :en)
      assert {:ok, "22nd"} = Rbnf.to_string(22, :digits_ordinal, locale: :en)
      assert {:ok, "100th"} = Rbnf.to_string(100, :digits_ordinal, locale: :en)
      assert {:ok, "123rd"} = Rbnf.to_string(123, :digits_ordinal, locale: :en)
    end
  end

  describe "algorithmic number systems" do
    test "Roman numerals" do
      assert {:ok, "XLII"} = Localize.Number.System.to_system(42, :roman)
      assert {:ok, "MMXXIV"} = Localize.Number.System.to_system(2024, :roman)
      assert {:ok, "XIV"} = Localize.Number.System.to_system(14, :roman)
    end
  end

  describe "rule_names_for_locale/1" do
    test "returns rule names for English" do
      {:ok, names} = Rbnf.rule_names_for_locale(:en)
      assert is_list(names)
      assert "spellout_cardinal" in names or :spellout_cardinal in names
    end
  end

  # The parser must distinguish `>>` from `>>>` per TR35 §RBNF_Syntax.
  # Prior to this fix the grammar collapsed both forms into the same
  # `{modulo, nil}` AST node, which silently ignored the source-author's
  # intent in every locale that uses `>>>` (ak, ja, km, ko, lo, th, und,
  # yue-Hans, yue, zh-Hant, zh).
  describe "parser distinguishes >> from >>> (Bug A)" do
    alias Localize.Number.Rbnf.Rule

    test "→→ parses to {:modulo, nil}" do
      assert {:ok, [modulo: nil]} = Rule.parse("→→")
    end

    test "→→→ parses to {:modulo_preceding, nil}" do
      assert {:ok, [modulo_preceding: nil]} = Rule.parse("→→→")
    end

    test ">> and >>> ASCII forms also distinguish" do
      assert {:ok, [modulo: nil]} = Rule.parse(">>")
      assert {:ok, [modulo_preceding: nil]} = Rule.parse(">>>")
    end

    test "←← →→ produces a separator literal between quotient and modulo" do
      assert {:ok, [quotient: nil, literal: " ", modulo: nil]} = Rule.parse("←← →→")
    end

    test "←← →→→ produces the preceding-modulo variant" do
      assert {:ok, [quotient: nil, literal: " ", modulo_preceding: nil]} =
               Rule.parse("←← →→→")
    end

    test ">>> next to a literal still parses cleanly" do
      assert {:ok, [literal: "三点", modulo_preceding: nil]} = Rule.parse("三点→→→")
    end
  end

  # Regression: locales whose `x.x` rules use `>>>` must concatenate
  # the per-digit fraction output without a separator. CJK locales
  # rely on this — `三点一四`, not `三点一 四`.
  describe ">>> in fractional rules (Bug A — CJK locales)" do
    test "Chinese 3.14 has no space between fractional digits" do
      assert {:ok, "三点一四"} = Rbnf.to_string(3.14, "spellout-numbering", locale: :zh)
    end

    test "Chinese 1.234 stays joined" do
      assert {:ok, "一点二三四"} = Rbnf.to_string(1.234, "spellout-numbering", locale: :zh)
    end

    test "Japanese 3.14 has no space between fractional digits" do
      assert {:ok, "三・一四"} = Rbnf.to_string(3.14, "spellout-numbering", locale: :ja)
    end

    test "Korean 3.14 has no space between fractional digits" do
      assert {:ok, "삼점일사"} = Rbnf.to_string(3.14, "spellout-numbering", locale: :ko)
    end

    test "Korean 0.123 has no space between fractional digits" do
      assert {:ok, "공점일이삼"} = Rbnf.to_string(0.123, "spellout-numbering", locale: :ko)
    end

    test "Cantonese-Simplified 3.14 has no space (yue-Hans uses >>>)" do
      assert {:ok, result} = Rbnf.to_string(3.14, "spellout-numbering", locale: :"yue-Hans")
      refute String.contains?(result, " ")
    end

    test "no inter-digit ASCII space across CJK/SEA spellout-numbering output" do
      # Sweep the locales whose `x.x` rule uses `→→→`. zh-Hant is
      # currently excluded because it also exercises Bug H (quotient
      # with rule arg on a float — a separate bug fixed later in this
      # plan). Once Bug H lands, add :"zh-Hant" back to this list.
      for locale <- [:zh, :ja, :ko, :th, :lo, :km] do
        {:ok, result} = Rbnf.to_string(3.14, "spellout-numbering", locale: locale)

        refute String.contains?(result, " "),
               "expected no ASCII space in #{locale} spellout-numbering 3.14, got #{inspect(result)}"
      end
    end
  end

  # Regression: locales whose `x.x` rules use `>>` (rather than `>>>`)
  # must continue to insert a literal space between fractional digits —
  # English and German depend on this for "three point one four" and
  # "drei Komma eins vier".
  describe ">> in fractional rules preserves space-joining (Bug A regression)" do
    test "English 3.14 keeps the space-separated digit names" do
      assert {:ok, "three point one four"} =
               Rbnf.to_string(3.14, "spellout-numbering", locale: :en)
    end

    test "English 1.234 keeps spaces across all fractional digits" do
      assert {:ok, "one point two three four"} =
               Rbnf.to_string(1.234, "spellout-numbering", locale: :en)
    end

    test "German 3.14 keeps the space-separated digit names" do
      assert {:ok, "drei Komma eins vier"} =
               Rbnf.to_string(3.14, "spellout-numbering", locale: :de)
    end

    test "French 3.14 (gendered cardinal) keeps the space-separated digit names" do
      assert {:ok, "trois virgule un quatre"} =
               Rbnf.to_string(3.14, "spellout-cardinal-masculine", locale: :fr)
    end
  end

  # Wider regression coverage for non-fraction operators that share
  # the parser/processor changes touched by Bug A: pure-integer paths
  # using >>, <<, =%name=, =#,##0=, [...], -x, $(ordinal,...), and
  # Russian gendered selection. If the parser change accidentally
  # damaged any of these the tests will fail.
  describe "non-fraction operator regressions (Bug A)" do
    test ">> on the spellout-numbering-year pattern (uses %%2d-year)" do
      assert {:ok, "nineteen eighty-five"} =
               Rbnf.to_string(1985, "spellout-numbering-year", locale: :en)
    end

    test "[...] optional sub-expression (en `twenty[-→→]`)" do
      assert {:ok, "twenty"} = Rbnf.to_string(20, "spellout-cardinal", locale: :en)
      assert {:ok, "twenty-one"} = Rbnf.to_string(21, "spellout-cardinal", locale: :en)
    end

    test "=#,##0= with $(ordinal,...) plural-keyed substitution" do
      assert {:ok, "11th"} = Rbnf.to_string(11, "digits-ordinal", locale: :en)
      assert {:ok, "21st"} = Rbnf.to_string(21, "digits-ordinal", locale: :en)
      assert {:ok, "23rd"} = Rbnf.to_string(23, "digits-ordinal", locale: :en)
      assert {:ok, "101st"} = Rbnf.to_string(101, "digits-ordinal", locale: :en)
    end

    test "Russian gendered cardinal selection still works" do
      assert {:ok, "один"} = Rbnf.to_string(1, "spellout-cardinal-masculine", locale: :ru)
      assert {:ok, "одна"} = Rbnf.to_string(1, "spellout-cardinal-feminine", locale: :ru)
    end

    test "Roman numerals (algorithmic, no fraction)" do
      assert {:ok, "MCMXCIX"} = Rbnf.to_string(1999, "roman-upper", locale: :en)
      assert {:ok, "MMXXVI"} = Rbnf.to_string(2026, "roman-upper", locale: :en)
    end

    test "negative integers (-x rule chained with >>)" do
      assert {:ok, "minus twenty-one"} =
               Rbnf.to_string(-21, "spellout-cardinal", locale: :en)
    end
  end
end
