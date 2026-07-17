defmodule Localize.Number.NumberSystemOverrideTest do
  use ExUnit.Case, async: true

  # Regression tests for numbering-system overrides, per TR35/ICU:
  # a `-u-nu-` locale keyword or an explicit `:number_system` option
  # is honoured for any numbering system in the CLDR inventory, even
  # when the locale does not list it. Formats and symbols inherit
  # from the locale's default system (CLDR root aliases them to
  # `latn`); digits come from the requested system.
  #
  # `en-u-nu-thai` used to be misrouted into the RBNF ruleset lookup
  # and returned `UnknownRbnfRuleError` for rule `:standard`.

  describe "-u-nu- numeric system override" do
    test "formats Thai digits in an en locale" do
      assert {:ok, "๑,๒๓๔.๕"} = Localize.Number.to_string(1234.5, locale: "en-u-nu-thai")
    end

    test "formats Devanagari digits in an en locale" do
      assert {:ok, "१,२३४.५"} = Localize.Number.to_string(1234.5, locale: "en-u-nu-deva")
    end

    test "nu override matching the locale default is a no-op" do
      assert {:ok, "1,234.5"} = Localize.Number.to_string(1234.5, locale: "en-u-nu-latn")
    end

    test "nu override for a system the locale lists natively" do
      assert {:ok, "๑,๒๓๔.๕"} = Localize.Number.to_string(1234.5, locale: "th-u-nu-thai")
    end

    test "unknown nu value is an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Number.to_string(1234.5, locale: "en-u-nu-bogus")
    end
  end

  describe ":number_system option with a system the locale does not list" do
    test "formats Thai digits in an en locale" do
      assert {:ok, "๑,๒๓๔.๕"} =
               Localize.Number.to_string(1234.5, locale: :en, number_system: :thai)
    end

    test "currency format transliterates digits but keeps locale symbols" do
      assert {:ok, "$๑,๒๓๔.๕๐"} =
               Localize.Number.to_string(1234.5,
                 locale: "en-u-nu-thai",
                 currency: :USD,
                 format: :currency
               )
    end

    test "percent format transliterates digits" do
      assert {:ok, "๕๐%"} =
               Localize.Number.to_string(0.5, locale: :en, number_system: :thai, format: :percent)
    end
  end

  describe "algorithmic number systems" do
    test "standard format uses the system's RBNF rules" do
      assert {:ok, "一千二百三十四"} =
               Localize.Number.to_string(1234, locale: :zh, number_system: :hans)
    end

    test "roman numerals via -u-nu-" do
      assert {:ok, "MCCXXXIV"} = Localize.Number.to_string(1234, locale: "en-u-nu-roman")
    end

    test "non-standard formats degrade to the default system's pattern" do
      assert {:ok, "50%"} =
               Localize.Number.to_string(0.5, locale: :zh, number_system: :hans, format: :percent)
    end
  end

  describe "data accessor fallback" do
    test "formats_for/2 inherits from the default system" do
      assert {:ok, formats} = Localize.Number.Format.formats_for(:en, :thai)
      assert formats.standard == "#,##0.###"
    end

    test "formats_for/2 fills nil fields of a partial entry" do
      # zh carries a :hans formats entry with no patterns of its own;
      # each field inherits from the default (latn) entry.
      assert {:ok, formats} = Localize.Number.Format.formats_for(:zh, :hans)
      assert is_binary(formats.percent)
    end

    test "number_symbols_for/2 falls back to the default system" do
      assert {:ok, symbols} = Localize.Number.Symbol.number_symbols_for(:en, :thai)
      assert %{standard: "."} = symbols.decimal
    end

    test "number_symbols_for/2 still errors for an unknown system" do
      assert {:error, _} = Localize.Number.Symbol.number_symbols_for(:en, :nonsense_xyz)
    end
  end
end
