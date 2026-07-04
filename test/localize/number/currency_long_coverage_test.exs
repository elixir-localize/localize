defmodule Localize.Number.CurrencyLongCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Number
  alias Localize.Number.Format.Options
  alias Localize.Number.Formatter.Currency

  describe ":currency_long_with_symbol format" do
    test "fills the plural pattern with the symbol-formatted number" do
      assert Number.to_string(123, format: :currency_long_with_symbol, currency: :USD) ==
               {:ok, "$123.00 US dollars"}
    end

    test "singular currency name for one" do
      assert Number.to_string(1, format: :currency_long_with_symbol, currency: :USD) ==
               {:ok, "$1.00 US dollar"}
    end

    test "Decimal input in a German locale" do
      assert Number.to_string(Decimal.new("1234.56"),
               format: :currency_long_with_symbol,
               currency: :EUR,
               locale: "de"
             ) == {:ok, "1.234,56 € Euro"}
    end

    test "French locale with pounds sterling" do
      assert Number.to_string(2,
               format: :currency_long_with_symbol,
               currency: :GBP,
               locale: "fr"
             ) == {:ok, "2,00 £GB livres sterling"}
    end

    test "explicit fractional digits are applied to the symbol part" do
      assert Number.to_string(1.5,
               format: :currency_long_with_symbol,
               currency: :USD,
               fractional_digits: 1
             ) == {:ok, "$1.5 US dollars"}
    end

    test "currency defaults from the locale when not given" do
      assert Number.to_string(123, format: :currency_long_with_symbol) ==
               {:ok, "$123.00 US dollars"}
    end

    test "invalid locale returns an InvalidLocaleError" do
      assert {:error, %Localize.InvalidLocaleError{locale_id: "xx"}} =
               Number.to_string(123,
                 format: :currency_long_with_symbol,
                 currency: :USD,
                 locale: "xx"
               )
    end

    test "number system not defined for the locale returns an error" do
      assert {:error, %Localize.UnknownNumberSystemError{number_system: :arab}} =
               Number.to_string(123,
                 format: :currency_long_with_symbol,
                 currency: :USD,
                 number_system: :arab
               )
    end

    test "string input returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{}} =
               Number.to_string("abc", format: :currency_long_with_symbol, currency: :USD)
    end
  end

  describe ":currency_long error propagation" do
    test "unknown number system returns an error" do
      assert {:error, %Localize.UnknownNumberSystemError{number_system: :bogus}} =
               Number.to_string(123,
                 format: :currency_long,
                 currency: :USD,
                 number_system: :bogus
               )
    end

    test "zero uses the plural currency name" do
      assert Number.to_string(0, format: :currency_long, currency: :USD) ==
               {:ok, "0 US dollars"}
    end

    test "explicit fractional digits override the currency-long default of zero" do
      assert Number.to_string(123, format: :currency_long, currency: :USD, fractional_digits: 2) ==
               {:ok, "123.00 US dollars"}
    end
  end

  describe "direct formatter clauses" do
    test "binary input is rejected by the formatter itself" do
      {:ok, options} = Options.validate_options(123, currency: :USD, format: :currency_long)

      assert {:error,
              %Localize.InvalidValueError{
                value: "abc",
                expected: "a number (not a string)"
              }} = Currency.to_string("abc", :currency_long, options)
    end

    test "a nil currency produces an empty display name" do
      {:ok, options} = Options.validate_options(123, currency: :USD, format: :currency_long)
      options_without_currency = Map.put(options, :currency, nil)

      assert Currency.to_string(123, :currency_long, options_without_currency) ==
               {:ok, "123 "}
    end

    test "a currency without plural counts falls back to its name" do
      # Regression: the pluralized clause matched every Currency struct
      # (the :count field always exists), so the name fallback was
      # unreachable and a nil :count crashed pluralize/3.
      {:ok, options} = Options.validate_options(123, currency: :USD, format: :currency_long)
      currency_without_counts = %{options.currency | count: nil}
      options = Map.put(options, :currency, currency_without_counts)

      assert Currency.to_string(123, :currency_long, options) == {:ok, "123 US Dollar"}
    end

    test "a currency with an empty plural count map falls back to its name" do
      {:ok, options} = Options.validate_options(123, currency: :USD, format: :currency_long)
      currency_with_empty_counts = %{options.currency | count: %{}}
      options = Map.put(options, :currency, currency_with_empty_counts)

      assert Currency.to_string(123, :currency_long, options) == {:ok, "123 US Dollar"}
    end
  end
end
