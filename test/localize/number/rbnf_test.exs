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
      # After Bug E, ko 0.123 routes through the `0.x` rule (sino-
      # Korean integer zero `영` instead of native `공`); the
      # important assertion for Bug A is the absence of a space.
      assert {:ok, "영점일이삼"} = Rbnf.to_string(0.123, "spellout-numbering", locale: :ko)
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

  # Regression: leading and embedded zeros in the fractional part
  # must be preserved. Prior to this fix `Digits.fraction_as_integer/1`
  # collapsed `0.05` to `5` and `3.04` to `4`, so locales whose `x.x`
  # rule formats the fraction digit-by-digit lost zeros and produced
  # `三点四` instead of `三点〇四`.
  describe "leading and embedded zeros in fractional digits (Bug C)" do
    test "English preserves a single leading-zero fraction digit" do
      assert {:ok, "zero point zero five"} =
               Rbnf.to_string(0.05, "spellout-numbering", locale: :en)
    end

    test "English preserves an embedded zero (1.05)" do
      assert {:ok, "one point zero five"} =
               Rbnf.to_string(1.05, "spellout-numbering", locale: :en)
    end

    test "English preserves multiple zeros (1.005)" do
      assert {:ok, "one point zero zero five"} =
               Rbnf.to_string(1.005, "spellout-numbering", locale: :en)
    end

    test "English preserves a leading-zero fraction with two more digits (0.025)" do
      assert {:ok, "zero point zero two five"} =
               Rbnf.to_string(0.025, "spellout-numbering", locale: :en)
    end

    test "Chinese preserves an embedded zero (3.04 → 三点〇四)" do
      assert {:ok, "三点〇四"} = Rbnf.to_string(3.04, "spellout-numbering", locale: :zh)
    end

    test "Chinese preserves an embedded zero with leading 1 (1.05 → 一点〇五)" do
      assert {:ok, "一点〇五"} = Rbnf.to_string(1.05, "spellout-numbering", locale: :zh)
    end

    test "Chinese preserves two embedded zeros (1.005 → 一点〇〇五)" do
      assert {:ok, "一点〇〇五"} = Rbnf.to_string(1.005, "spellout-numbering", locale: :zh)
    end

    test "Korean preserves a leading zero in the fraction (0.05)" do
      # After Bug E ko 0.05 routes through the `0.x` rule:
      # integer 0 → sino-Korean `영`; fraction digits go via
      # spellout-numbering selection (digit 0 → 공, digit 5 → 오).
      # The test's job is to assert the leading-zero digit in the
      # fraction reaches the formatter at all (Bug C).
      assert {:ok, "영점공오"} = Rbnf.to_string(0.05, "spellout-numbering", locale: :ko)
    end

    test "Korean preserves multiple zeros in the fraction (0.005)" do
      assert {:ok, "영점공공오"} = Rbnf.to_string(0.005, "spellout-numbering", locale: :ko)
    end

    test "Korean preserves a leading zero followed by two more digits (0.025)" do
      assert {:ok, "영점공이오"} = Rbnf.to_string(0.025, "spellout-numbering", locale: :ko)
    end

    test "Japanese preserves an embedded zero in the fraction (3.04)" do
      assert {:ok, result} = Rbnf.to_string(3.04, "spellout-numbering", locale: :ja)
      # Two digits in the fraction should be present (one zero, one four).
      assert String.length(result) >= 4,
             "expected fractional digits preserved, got #{inspect(result)}"
    end

    test "Integer-valued floats keep the existing 'point zero' tail" do
      # `1.0` matches the `x.x` rule even though the fraction is
      # zero. Preserve the prior behaviour (a single 'zero' digit)
      # rather than emitting a trailing literal-only 'point '.
      assert {:ok, "one point zero"} = Rbnf.to_string(1.0, "spellout-numbering", locale: :en)
      assert {:ok, "zero point zero"} = Rbnf.to_string(0.0, "spellout-numbering", locale: :en)
    end
  end

  # Regression: very small fractions used to truncate. Prior to the
  # `fractional_digit_list/1` reshape (Bug C), `0.000001` rendered as
  # `"zero point one"` because `Digits.fraction_as_integer/1` returned
  # `1` and the `e-6` magnitude was discarded. The same root cause as
  # Bug C, so the same fix closes both — these tests lock in the
  # small-fraction behaviour separately so a regression in either
  # direction (embedded zero vs leading-zero count) is caught
  # independently.
  describe "small-magnitude fractions (Bug D)" do
    test "0.0001 (four leading zeros)" do
      assert {:ok, "zero point zero zero zero one"} =
               Rbnf.to_string(0.0001, "spellout-numbering", locale: :en)
    end

    test "0.00001 (five leading zeros)" do
      assert {:ok, "zero point zero zero zero zero one"} =
               Rbnf.to_string(0.00001, "spellout-numbering", locale: :en)
    end

    test "0.000001 (six leading zeros — original Bug D repro)" do
      assert {:ok, "zero point zero zero zero zero zero one"} =
               Rbnf.to_string(0.000001, "spellout-numbering", locale: :en)
    end

    test "1.0e-7 scientific-notation literal — seven leading zeros" do
      assert {:ok, "zero point zero zero zero zero zero zero one"} =
               Rbnf.to_string(1.0e-7, "spellout-numbering", locale: :en)
    end

    test "0.012345 mixed leading-zero plus more digits" do
      assert {:ok, "zero point zero one two three four five"} =
               Rbnf.to_string(0.012345, "spellout-numbering", locale: :en)
    end

    test "0.123456 no leading zero, full precision preserved" do
      assert {:ok, "zero point one two three four five six"} =
               Rbnf.to_string(0.123456, "spellout-numbering", locale: :en)
    end

    test "small Chinese fraction stays glued (zh + Bug A + Bug C + Bug D)" do
      # Compounds three fixes: `>>>` no separator, leading zeros
      # preserved, magnitude not truncated.
      assert {:ok, "〇点〇〇〇〇〇一"} =
               Rbnf.to_string(0.000001, "spellout-numbering", locale: :zh)
    end
  end

  # Per TR35, when the integer part is zero but the value is
  # non-zero (e.g. `0.5`, `0.05`), the matcher must prefer a `0.x`
  # rule over `x.x` if the locale defines one. Currently used by
  # `ee` and `ko`. Folds in the float-quotient-with-rule clause
  # (originally tracked separately as Bug H) because ko's `0.x`
  # body uses `<%spellout-cardinal-sinokorean<` which crashed on
  # floats.
  describe "0.x rule selection for sub-1 floats (Bug E + folded Bug H)" do
    test "ko 0.5 uses the 0.x rule (sino-Korean integer zero, 영)" do
      assert {:ok, "영점오"} = Rbnf.to_string(0.5, "spellout-numbering", locale: :ko)
    end

    test "ko 0.05 uses the 0.x rule with leading-zero fraction" do
      # Integer side: sino-Korean 0 = 영. Fraction digits go through
      # spellout-numbering rule selection: digit 0 → 공 (rule `0`),
      # digit 5 → 오 (rule `1` → spellout-cardinal-sinokorean).
      assert {:ok, "영점공오"} = Rbnf.to_string(0.05, "spellout-numbering", locale: :ko)
    end

    test "ko 0.025 uses the 0.x rule" do
      assert {:ok, "영점공이오"} = Rbnf.to_string(0.025, "spellout-numbering", locale: :ko)
    end

    test "ko 0.123 uses the 0.x rule" do
      assert {:ok, "영점일이삼"} = Rbnf.to_string(0.123, "spellout-numbering", locale: :ko)
    end

    test "ee 0.5 uses the 0.x rule" do
      # ee's 0.x body is `kakɛ →→` — `<<` is implicit via the
      # literal, the integer part is dropped, and `→→` formats
      # the digit via the same rule set.
      assert {:ok, "kakɛ atɔ̃"} = Rbnf.to_string(0.5, "spellout-numbering", locale: :ee)
    end

    test "ee 0.05 uses the 0.x rule with leading-zero fraction" do
      # `→→` (not `→→→`), so digits join with a space.
      assert {:ok, "kakɛ ɖekeo atɔ̃"} =
               Rbnf.to_string(0.05, "spellout-numbering", locale: :ee)
    end

    test "ko 1.5 must NOT match 0.x; falls back to x.x" do
      assert {:ok, "일점오"} = Rbnf.to_string(1.5, "spellout-numbering", locale: :ko)
    end

    test "ko 3.14 must NOT match 0.x; falls back to x.x" do
      assert {:ok, "삼점일사"} = Rbnf.to_string(3.14, "spellout-numbering", locale: :ko)
    end

    test "ko 0.0 must NOT match 0.x (value is zero); falls back to x.x" do
      assert {:ok, "공점공"} = Rbnf.to_string(0.0, "spellout-numbering", locale: :ko)
    end

    test "locales without 0.x continue to use x.x for sub-1 floats" do
      assert {:ok, "〇点五"} = Rbnf.to_string(0.5, "spellout-numbering", locale: :zh)
      assert {:ok, "zero point five"} = Rbnf.to_string(0.5, "spellout-numbering", locale: :en)
      assert {:ok, "null Komma fünf"} = Rbnf.to_string(0.5, "spellout-numbering", locale: :de)
    end
  end

  # Bug H is folded into Bug E because ko's `0.x` rule body needs
  # the float-quotient-with-rule clause to run end-to-end. Adding
  # a synthetic standalone test pins the clause separately so a
  # future regression that breaks one but not the other surfaces
  # cleanly.
  describe "float quotient with named rule and decimal format (Bug H)" do
    alias Localize.Number.Rbnf.Processor

    test "<%name< on a float dispatches to the named rule on the integer part" do
      # Synthetic: rule body `←%spellout-cardinal← point →→`
      # applied to 3.5. `<%spellout-cardinal<` should format the
      # truncated integer 3 via spellout-cardinal.
      rules = [
        %{
          base_value: "x.x",
          definition: "←%spellout-cardinal← point →→",
          divisor: 1,
          radix: 10,
          range: "undefined"
        }
      ]

      # Use the en locale's rule sets so spellout-cardinal exists.
      {:ok, rbnf} = Localize.Locale.get(:en, [:rbnf])

      all_sets =
        Enum.reduce(rbnf, %{}, fn {_group, sets}, acc ->
          if is_map(sets), do: Map.merge(acc, sets), else: acc
        end)

      assert {:ok, result} = Processor.process(3.5, "synthetic", rules, all_sets)
      assert String.starts_with?(result, "three"), "got #{inspect(result)}"
      assert String.contains?(result, "point")
    end

    test "<#,##0< on a float dispatches to the decimal pattern" do
      rules = [
        %{
          base_value: "x.x",
          definition: "←#,##0← point →→",
          divisor: 1,
          radix: 10,
          range: "undefined"
        }
      ]

      {:ok, rbnf} = Localize.Locale.get(:en, [:rbnf])

      all_sets =
        Enum.reduce(rbnf, %{}, fn {_group, sets}, acc ->
          if is_map(sets), do: Map.merge(acc, sets), else: acc
        end)

      assert {:ok, result} = Processor.process(1234.5, "synthetic", rules, all_sets)
      assert String.starts_with?(result, "1,234"), "got #{inspect(result)}"
      assert String.contains?(result, "point")
    end
  end

  # Bug F covers two related symptoms.
  #
  # 1. Original repro: `-0.5 ko spellout-numbering` produced
  #    `공점공점오` because the `:modulo` clause's negative-handling
  #    arm recursed via `apply_rule_set(abs(...), rule_set, ...)`,
  #    which re-walked the entire `x.x` rule body. The doubling is
  #    eliminated by Bug A (separate `:modulo_preceding` AST node)
  #    plus Bug E (rerouting `0.5` through the `0.x` rule).
  #
  # 2. Residual issue: when a locale's rule set has no `-x` rule
  #    (e.g. ko `spellout-numbering`), the sign was silently
  #    dropped. Now `process/4` synthesizes a `-` prefix when the
  #    matched rule is a *special-base* rule (`0.x`, `x.x`, `x,x`,
  #    `Inf`, `NaN`) other than `-x`. Integer-base rules continue
  #    to delegate to other rule sets (whose `-x` handler emits
  #    the locale-correct word).
  describe "negative floats (Bug F)" do
    test "ko -0.5 (no -x; integer side delegates via 0.x — minus prefix synthesized)" do
      assert {:ok, "-영점오"} = Rbnf.to_string(-0.5, "spellout-numbering", locale: :ko)
    end

    test "ko -0.05 (leading-zero fraction, sign preserved)" do
      assert {:ok, "-영점공오"} = Rbnf.to_string(-0.05, "spellout-numbering", locale: :ko)
    end

    test "ko -0.123 (no doubling; sign preserved)" do
      assert {:ok, "-영점일이삼"} = Rbnf.to_string(-0.123, "spellout-numbering", locale: :ko)
    end

    test "ko -3.14 falls through x.x; sign preserved with synthetic prefix" do
      # ko spellout-numbering has no -x and matches x.x for >=1
      # negative floats. The -x.x special base triggers the
      # process-level minus synthesis.
      assert {:ok, "-삼점일사"} = Rbnf.to_string(-3.14, "spellout-numbering", locale: :ko)
    end

    test "ko -123 delegates to spellout-cardinal-sinokorean which has -x" do
      # base_value 0 (or another integer) matches; the rule body
      # `=%spellout-cardinal-sinokorean=` recurses; that rule set
      # has its own -x handler producing 마이너스. We must NOT
      # synthesize a "-" prefix here.
      assert {:ok, "마이너스 백이십삼"} =
               Rbnf.to_string(-123, "spellout-numbering", locale: :ko)
    end

    test "en -3.14 keeps its locale-correct 'minus' word" do
      assert {:ok, "minus three point one four"} =
               Rbnf.to_string(-3.14, "spellout-numbering", locale: :en)
    end

    test "en -0.5 keeps its locale-correct 'minus' word" do
      assert {:ok, "minus zero point five"} =
               Rbnf.to_string(-0.5, "spellout-numbering", locale: :en)
    end

    test "en -1985 (integer) keeps its 'minus' word" do
      assert {:ok, "minus one thousand nine hundred eighty-five"} =
               Rbnf.to_string(-1985, "spellout-numbering", locale: :en)
    end

    test "de -3.14 keeps its 'minus' word" do
      assert {:ok, "minus drei Komma eins vier"} =
               Rbnf.to_string(-3.14, "spellout-numbering", locale: :de)
    end

    test "zh -3.14 keeps its '负' word (regression check for ja/zh delegation)" do
      assert {:ok, "负三点一四"} = Rbnf.to_string(-3.14, "spellout-numbering", locale: :zh)
    end

    test "ja -3.14 delegates to spellout-cardinal whose -x emits マイナス" do
      # Critical regression test. ja spellout-numbering is one
      # rule (base_value 0) `=%spellout-cardinal=`. The cardinal
      # rule set has -x. We must NOT synthesize a "-" prefix
      # because that would suppress マイナス.
      assert {:ok, "マイナス三・一四"} =
               Rbnf.to_string(-3.14, "spellout-numbering", locale: :ja)
    end

    test "fr -3.14 spellout-cardinal-masculine keeps 'moins' (delegation)" do
      assert {:ok, "moins trois virgule un quatre"} =
               Rbnf.to_string(-3.14, "spellout-cardinal-masculine", locale: :fr)
    end

    test "ee -0.5 retains its -x word (suffix form)" do
      # ee's -x rule appends a suffix rather than prefixing.
      assert {:ok, result} = Rbnf.to_string(-0.5, "spellout-numbering", locale: :ee)
      assert String.contains?(result, "xlẽyimegbee"),
             "expected ee's negative-suffix word, got #{inspect(result)}"
    end

    test "positive cases are unaffected" do
      assert {:ok, "영점오"} = Rbnf.to_string(0.5, "spellout-numbering", locale: :ko)
      assert {:ok, "삼점일사"} = Rbnf.to_string(3.14, "spellout-numbering", locale: :ko)
      assert {:ok, "three point one four"} =
               Rbnf.to_string(3.14, "spellout-numbering", locale: :en)
      assert {:ok, "三点一四"} = Rbnf.to_string(3.14, "spellout-numbering", locale: :zh)
    end
  end

  # `<#,##0<` (integer quotient via decimal format) used to raise
  # `no case clause matching: {:format, "..."}` because the
  # integer quotient handler's case had no `{:format, _}` clause.
  # Real CLDR data exercises this in ky's `%%z-spellout-fraction`
  # private rule set (called from the `x.x` rule). The same gap
  # also existed for `:modulo` on floats with `{:rule, _}` and
  # `{:format, _}` arguments, which used to raise
  # `FunctionClauseError`.
  describe "quotient/modulo with decimal-format and named-rule arguments (Bug G)" do
    alias Localize.Number.Rbnf.{Processor, Rule}

    test "<#,##0< on integer dispatches the divisor through the decimal pattern" do
      # Synthetic rule: base 100 / divisor 100. For input 250
      # the quotient is `div(250, 100) = 2`, formatted via the
      # `#,##0` pattern → `"2"`.
      {:ok, _} = Rule.parse("←#,##0←")

      rules = [
        %{
          base_value: 100,
          definition: "←#,##0←",
          divisor: 100,
          radix: 10,
          range: "undefined"
        }
      ]

      assert {:ok, "2"} = Processor.process(250, "synthetic", rules, %{})
    end

    test "<#,##0< on integer with larger divisor" do
      {:ok, _} = Rule.parse("←#,##0← thousands")

      rules = [
        %{
          base_value: 1_000,
          definition: "←#,##0← thousands",
          divisor: 1_000,
          radix: 10,
          range: "undefined"
        }
      ]

      assert {:ok, "12 thousands"} = Processor.process(12_345, "synthetic", rules, %{})
    end

    test "ky 1_000_000_000_000 spellout-cardinal still works (regression)" do
      # spellout-cardinal's 10^12 rule is just a literal "триллион";
      # this test pins that path so a future `<#,##0<` regression in
      # Processor doesn't break it.
      assert {:ok, "триллион"} =
               Rbnf.to_string(1_000_000_000_000, "spellout-cardinal", locale: :ky)
    end

    test "ky 1.5 spellout-cardinal does not crash on >%name>" do
      # x.x rule body: `←← бүтүн →%%z-spellout-fraction→`.
      # Pre-fix: FunctionClauseError. Post-fix: no crash.
      # Output is best-effort (missing the locale's denominator
      # word — see plans/rbnf.md for the full numerator/
      # denominator implementation).
      assert {:ok, result} = Rbnf.to_string(1.5, "spellout-cardinal", locale: :ky)
      assert is_binary(result)
      assert String.contains?(result, "бир"), "expected 'бир' (one), got #{inspect(result)}"
      assert String.contains?(result, "бүтүн"), "expected 'бүтүн' (whole), got #{inspect(result)}"
    end

    test "ky 0.5 spellout-cardinal does not crash on >%name>" do
      assert {:ok, result} = Rbnf.to_string(0.5, "spellout-cardinal", locale: :ky)
      assert is_binary(result)
      assert String.contains?(result, "нөл"), "expected 'нөл' (zero), got #{inspect(result)}"
    end

    test "ky 12.345 spellout-cardinal does not crash on multi-digit fraction" do
      assert {:ok, result} = Rbnf.to_string(12.345, "spellout-cardinal", locale: :ky)
      assert is_binary(result)
      # Assertion is intentionally loose; specific output depends
      # on the fractional-numerator algorithm.
      refute String.starts_with?(result, "{:error"), "got #{inspect(result)}"
    end

    test "<#,##0< on float (synthetic) returns the truncated integer pattern" do
      # Pre-Bug-H this crashed; Bug E + folded H added the float
      # quotient clause. Pin it from this test as well.
      rules = [
        %{
          base_value: "x.x",
          definition: "←#,##0← point →→",
          divisor: 1,
          radix: 10,
          range: "undefined"
        }
      ]

      {:ok, rbnf} = Localize.Locale.get(:en, [:rbnf])

      all_sets =
        Enum.reduce(rbnf, %{}, fn {_g, s}, acc ->
          if is_map(s), do: Map.merge(acc, s), else: acc
        end)

      assert {:ok, result} = Processor.process(1234.5, "synthetic", rules, all_sets)
      assert String.starts_with?(result, "1,234")
      assert String.contains?(result, "point")
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
