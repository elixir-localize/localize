defmodule Localize.Unit.FormatterTest do
  use ExUnit.Case, async: true

  doctest Localize.Unit

  alias Localize.Unit

  describe "to_string/2 with simple units" do
    test "formats meter in long style" do
      {:ok, unit} = Unit.new(42, "meter")
      assert {:ok, "42 meters"} = Unit.to_string(unit)
    end

    test "formats singular meter" do
      {:ok, unit} = Unit.new(1, "meter")
      assert {:ok, "1 meter"} = Unit.to_string(unit)
    end

    test "formats in short style" do
      {:ok, unit} = Unit.new(42, "meter")
      assert {:ok, "42 m"} = Unit.to_string(unit, format: :short)
    end

    test "formats in narrow style" do
      {:ok, unit} = Unit.new(42, "meter")
      {:ok, result} = Unit.to_string(unit, format: :narrow)
      assert String.contains?(result, "42")
      assert String.contains?(result, "m")
    end

    test "formats kilogram" do
      {:ok, unit} = Unit.new(2.5, "kilogram")
      {:ok, result} = Unit.to_string(unit)
      assert String.contains?(result, "kilogram")
    end

    test "formats celsius" do
      {:ok, unit} = Unit.new(100, "celsius")
      {:ok, result} = Unit.to_string(unit, format: :short)
      assert String.contains?(result, "°C")
    end
  end

  describe "to_string/2 with compound units" do
    test "formats mile-per-hour in long style" do
      {:ok, unit} = Unit.new(60, "mile-per-hour")
      assert {:ok, "60 miles per hour"} = Unit.to_string(unit)
    end

    test "formats mile-per-hour in short style" do
      {:ok, unit} = Unit.new(60, "mile-per-hour")
      assert {:ok, "60 mph"} = Unit.to_string(unit, format: :short)
    end
  end

  describe "to_string/2 with per-compounds that have no direct CLDR pattern" do
    test "composes foot-per-second from the numerator and per-pattern" do
      {:ok, unit} = Unit.new(2, "foot-per-second")
      assert {:ok, "2 feet per second"} = Unit.to_string(unit)
    end

    test "composes a singular pattern-less per-compound" do
      {:ok, unit} = Unit.new(1, "foot-per-second")
      assert {:ok, "1 foot per second"} = Unit.to_string(unit)
    end

    test "composes gram-per-hour" do
      {:ok, unit} = Unit.new(2, "gram-per-hour")
      assert {:ok, "2 grams per hour"} = Unit.to_string(unit)
    end

    test "composes a pattern-less per-compound in short style" do
      {:ok, unit} = Unit.new(2, "foot-per-second")
      assert {:ok, "2 ft/s"} = Unit.to_string(unit, format: :short)
    end

    test "composes with a powered denominator" do
      {:ok, unit} = Unit.new(2, "pound-per-square-inch")
      assert {:ok, "2 pounds per square inch"} = Unit.to_string(unit)
    end

    test "composes in German using the locale per-pattern" do
      {:ok, unit} = Unit.new(2, "foot-per-second")
      assert {:ok, "2 Fuß pro Sekunde"} = Unit.to_string(unit, locale: :de)
    end

    test "still prefers a direct CLDR pattern when one exists" do
      {:ok, unit} = Unit.new(3, "meter-per-second")
      assert {:ok, "3 meters per second"} = Unit.to_string(unit)
    end
  end

  describe "to_string/2 with times-compounds that have no direct CLDR pattern (issue #43)" do
    test "composes tonne-kilometer from the component nouns and times pattern" do
      {:ok, unit} = Unit.new(5, "tonne-kilometer")
      assert {:ok, "5 metric ton-kilometers"} = Unit.to_string(unit)
    end

    test "keeps the leading component singular and pluralizes the trailing one" do
      {:ok, unit} = Unit.new(1, "tonne-kilometer")
      assert {:ok, "1 metric ton-kilometer"} = Unit.to_string(unit)
    end

    test "composes a times-compound in short style with the ⋅ pattern" do
      {:ok, unit} = Unit.new(5, "tonne-kilometer")
      # U+22C5 DOT OPERATOR joins the short unit symbols.
      assert {:ok, "5 t⋅km"} = Unit.to_string(unit, format: :short)
    end

    test "pluralizes every component in French per its CLDR times derivation" do
      {:ok, unit} = Unit.new(5, "tonne-kilometer")
      # French's grammaticalFeatures derivation sets times value0="compound",
      # so both components are plural (unlike the root default's leading
      # singular), and the number is separated by a non-breaking space
      # (U+00A0). This matches ICU exactly.
      assert {:ok, "5 tonnes-kilomètres"} = Unit.to_string(unit, locale: :fr)
    end

    test "still prefers a direct CLDR pattern for a precomposed times-compound" do
      {:ok, unit} = Unit.new(5, "newton-meter")
      assert {:ok, "5 newton-meters"} = Unit.to_string(unit)
    end
  end

  describe "to_string/2 with locales" do
    test "formats in German" do
      {:ok, unit} = Unit.new(2.5, "kilogram")
      {:ok, result} = Unit.to_string(unit, locale: :de)
      assert String.contains?(result, "Kilogramm")
    end

    test "formats in French" do
      {:ok, unit} = Unit.new(42, "meter")
      {:ok, result} = Unit.to_string(unit, locale: :fr)
      assert String.contains?(result, "mètre")
    end
  end

  describe "to_string/2 with zero and fractional values" do
    test "formats zero" do
      {:ok, unit} = Unit.new(0, "meter")
      {:ok, result} = Unit.to_string(unit)
      assert String.contains?(result, "0")
      assert String.contains?(result, "meter")
    end

    test "formats fractional value" do
      {:ok, unit} = Unit.new(1.5, "meter")
      {:ok, result} = Unit.to_string(unit)
      assert String.contains?(result, "1.5")
    end
  end

  describe "to_string/2 with Decimal values" do
    test "an integer-valued Decimal selects the :one plural form" do
      # Decimal "1" renders as "1" — v=0, so :one in en.
      assert Unit.to_string(Unit.new!(Decimal.new("1"), "meter")) == {:ok, "1 meter"}
    end

    test "a fraction the default pattern does not render does not reach the plural" do
      # Decimal "1.0" carries one decimal place, but the default pattern
      # (`#,##0.###`, minimum 0 fraction digits) renders it as "1". TR35
      # defines the operands over the source number — "the visual appearance
      # of the digits of the result" — so v=0 and the noun is singular. The
      # digits the reader sees decide, not the digits that went in.
      assert Unit.to_string(Unit.new!(Decimal.new("1.0"), "meter")) == {:ok, "1 meter"}
    end

    test "a fraction the pattern does render selects the :other plural form" do
      # The same Decimal, asked to show its decimal place: "1.0" is v=1, and
      # every visible fraction is :other in en.
      assert Unit.to_string(Unit.new!(Decimal.new("1.0"), "meter"), fractional_digits: 1) ==
               {:ok, "1.0 meters"}
    end

    test "a Decimal greater than one selects the :other plural form" do
      assert Unit.to_string(Unit.new!(Decimal.new("2"), "meter")) == {:ok, "2 meters"}
    end
  end

  # TR35 defines the plural operands over the source number, "the visual
  # appearance of the digits of the result", so the category has to follow the
  # formatted output. Selecting on the input value is wrong in both directions:
  # a fraction can be rendered away, and one can be added that was never there.
  describe "to_string/2 plural selection follows the rendered digits" do
    test "a float whose fraction is not rendered is singular" do
      assert Unit.to_string(Unit.new!(1.0, "hectare"), locale: "en") == {:ok, "1 hectare"}
      assert Unit.to_string(Unit.new!(1, "hectare"), locale: "en") == {:ok, "1 hectare"}
    end

    test "digits the options add are plural, whatever the input was" do
      # The converse case: nothing about the input 1 suggests a fraction, but
      # it renders as "1.00" and v=2 is :other in en.
      for value <- [1, 1.0, Decimal.new("1")] do
        assert Unit.to_string(Unit.new!(value, "hectare"), locale: "en", fractional_digits: 2) ==
                 {:ok, "1.00 hectares"},
               "#{inspect(value)} with two fraction digits should be plural"
      end
    end

    test "an integer and the float that renders identically agree" do
      # The whole class of bug in one assertion: if two values render the same
      # number, they must render the same noun.
      for {integer, float} <- [{1, 1.0}, {2, 2.0}, {0, 0.0}, {21, 21.0}],
          unit <- ~w(hectare meter second) do
        assert Unit.to_string(Unit.new!(integer, unit), locale: "en") ==
                 Unit.to_string(Unit.new!(float, unit), locale: "en"),
               "#{integer} and #{float} #{unit} rendered differently"
      end
    end

    test "across locales with richer plural systems" do
      # English only distinguishes one/other, so it hides most of this. Russian
      # and Czech separate few and many on the same v=0 operand.
      for locale <- ~w(ru cs pl ar he) do
        for {integer, float} <- [{1, 1.0}, {2, 2.0}, {5, 5.0}, {21, 21.0}] do
          assert Unit.to_string(Unit.new!(integer, "meter"), locale: locale) ==
                   Unit.to_string(Unit.new!(float, "meter"), locale: locale),
                 "#{locale}: #{integer} and #{float} meters rendered differently"
        end
      end
    end

    test "a genuinely visible fraction is still plural" do
      assert Unit.to_string(Unit.new!(1.5, "hectare"), locale: "en") == {:ok, "1.5 hectares"}
      assert Unit.to_string(Unit.new!(0.5, "hectare"), locale: "en") == {:ok, "0.5 hectares"}
    end

    test "the count comes from the rendered digits, not the localized glyphs" do
      # `hi-u-nu-deva` renders in Devanagari, so a plural derived by reading
      # the formatted string back would have to transliterate first.
      assert {:ok, formatted} = Unit.to_string(Unit.new!(1.0, "meter"), locale: "hi-u-nu-deva")
      assert {:ok, ^formatted} = Unit.to_string(Unit.new!(1, "meter"), locale: "hi-u-nu-deva")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      {:ok, unit} = Unit.new(42, "meter")
      assert "42 meters" = Unit.to_string!(unit)
    end
  end

  describe "to_string/2 without value" do
    test "returns display name when no value" do
      {:ok, unit} = Unit.new("meter")
      {:ok, result} = Unit.to_string(unit)
      assert result == "meters"
    end
  end
end
