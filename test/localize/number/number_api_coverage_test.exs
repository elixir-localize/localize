defmodule Localize.Number.ApiCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Number
  alias Localize.Number.Format.Options

  describe "to_string!/2" do
    test "returns the string directly" do
      assert Number.to_string!(1234) == "1,234"
    end

    test "raises on an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Number.to_string!(123, locale: "xx")
      end
    end
  end

  describe "to_string/2 with a validated Options struct" do
    test "formats without re-validating" do
      {:ok, options} = Options.validate_options(12, locale: "en", format: :standard)
      assert Number.to_string(12, options) == {:ok, "12"}
    end
  end

  describe "to_string/2 with the NIF backend" do
    @describetag :nif

    test "formats a number" do
      if Localize.Nif.available?() do
        assert Number.to_string(1234.5, backend: :nif) == {:ok, "1,234.5"}
      end
    end

    test "returns an error for an invalid locale" do
      if Localize.Nif.available?() do
        assert {:error, %Localize.InvalidLocaleError{}} =
                 Number.to_string(1, backend: :nif, locale: "zz-bogus")
      end
    end
  end

  describe "range and approximation wrappers" do
    test "to_range_string/3 with approximate: true uses the approximately pattern" do
      assert Number.to_range_string(3, 5, approximate: true) == {:ok, "~3"}
    end

    test "to_range_string!/3 returns the string directly" do
      assert Number.to_range_string!(3, 5) == "3–5"
    end

    test "to_range_string!/3 raises on error" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Number.to_range_string!(3, 5, locale: "xx")
      end
    end

    test "to_range_string!/2 accepts a Range" do
      assert Number.to_range_string!(3..5, []) == "3–5"
    end

    test "to_range_string!/2 raises on error" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Number.to_range_string!(3..5, locale: "xx")
      end
    end

    test "to_at_least_string!/2 returns the string directly" do
      assert Number.to_at_least_string!(5) == "5+"
    end

    test "to_at_least_string!/2 raises on error" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Number.to_at_least_string!(5, locale: "xx")
      end
    end

    test "to_at_most_string/2 and its bang variant" do
      assert Number.to_at_most_string(5) == {:ok, "≤5"}
      assert Number.to_at_most_string!(5) == "≤5"

      assert_raise Localize.InvalidLocaleError, fn ->
        Number.to_at_most_string!(5, locale: "xx")
      end
    end

    test "to_approximately_string!/2 returns the string directly" do
      assert Number.to_approximately_string!(5) == "~5"
    end

    test "to_approximately_string!/2 raises on error" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Number.to_approximately_string!(5, locale: "xx")
      end
    end
  end

  describe "ratio wrappers" do
    test "to_ratio_string!/2 returns the string directly" do
      assert Number.to_ratio_string!(0.25) == "1⁄4"
    end

    test "to_ratio_string!/2 raises on error" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Number.to_ratio_string!(0.1, locale: "xx")
      end
    end
  end

  describe "parser delegates" do
    test "scan/2 tokenizes numbers out of a string" do
      assert Number.scan("100 dollars and 50 cents") == [100, " dollars and ", 50, " cents"]
    end

    test "parse/2 parses a grouped decimal string" do
      assert Number.parse("1,234.56") == {:ok, 1234.56}
    end

    test "resolve_currencies/2 resolves currency tokens in a list" do
      assert Number.resolve_currencies(["100", "USD"]) == ["100", :USD]
    end

    test "resolve_currency/2 resolves a single currency string" do
      assert Number.resolve_currency("USD") == [:USD]
    end

    test "resolve_pers/2 resolves percent tokens in a list" do
      assert Number.resolve_pers(["5", "%"]) == ["5", :percent]
    end

    test "resolve_per/2 resolves a single percent string" do
      assert Number.resolve_per("%") == [:percent]
    end
  end

  describe "number system errors" do
    test "a number system not used by the locale returns an error" do
      assert {:error, %Localize.UnknownNumberSystemError{number_system: :thai}} =
               Number.to_string(1234, format: :standard, number_system: :thai)
    end
  end
end
