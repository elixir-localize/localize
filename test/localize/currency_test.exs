defmodule Localize.CurrencyTest do
  use ExUnit.Case, async: true

  doctest Localize.Currency

  alias Localize.Currency

  describe "known_currency_codes/0" do
    test "returns a non-empty list" do
      codes = Currency.known_currency_codes()
      assert is_list(codes)
      assert length(codes) > 0
    end

    test "includes common currency codes" do
      codes = Currency.known_currency_codes()
      assert :USD in codes
      assert :EUR in codes
      assert :GBP in codes
      assert :JPY in codes
      assert :AUD in codes
    end
  end

  describe "known_currency_code?/1" do
    test "returns true for known codes" do
      assert Currency.known_currency_code?(:USD)
      assert Currency.known_currency_code?(:EUR)
      assert Currency.known_currency_code?("AUD")
    end

    test "returns false for unknown codes" do
      refute Currency.known_currency_code?(:GGG)
      refute Currency.known_currency_code?("ZZZ")
    end
  end

  describe "validate_currency/1" do
    test "validates known currency codes as atoms" do
      assert {:ok, :USD} = Currency.validate_currency(:USD)
      assert {:ok, :EUR} = Currency.validate_currency(:EUR)
    end

    test "validates known currency codes as strings" do
      assert {:ok, :USD} = Currency.validate_currency("USD")
      assert {:ok, :AUD} = Currency.validate_currency("aud")
    end

    test "returns error for unknown codes" do
      assert {:error, %Localize.UnknownCurrencyError{}} =
               Currency.validate_currency(:GGG)
    end
  end

  describe "territory_currencies/0" do
    test "returns a map of territories" do
      territories = Currency.territory_currencies()
      assert is_map(territories)
      assert map_size(territories) > 0
    end

    test "US has USD" do
      territories = Currency.territory_currencies()
      assert Map.has_key?(territories[:US], :USD)
    end
  end

  describe "territory_currencies/1" do
    test "returns currencies for a known territory" do
      assert {:ok, currencies} = Currency.territory_currencies(:US)
      assert Map.has_key?(currencies, :USD)
    end

    test "accepts string territory codes" do
      assert {:ok, currencies} = Currency.territory_currencies("AU")
      assert Map.has_key?(currencies, :AUD)
    end

    test "returns error for unknown territory" do
      assert {:error, _} = Currency.territory_currencies(:UNKNOWN)
    end
  end

  describe "current_currency_for_territory/1" do
    test "returns the current currency for US" do
      assert :USD = Currency.current_currency_for_territory(:US)
    end

    test "returns the current currency for Australia" do
      assert :AUD = Currency.current_currency_for_territory(:AU)
    end

    test "returns the current currency for Japan" do
      assert :JPY = Currency.current_currency_for_territory(:JP)
    end

    test "accepts string territory codes" do
      assert :GBP = Currency.current_currency_for_territory("GB")
    end

    test "returns nil for territory with no current currency" do
      assert is_nil(Currency.current_currency_for_territory(:UNKNOWN))
    end
  end

  describe "current_territory_currencies/0" do
    test "returns a map of territory to current currency" do
      map = Currency.current_territory_currencies()
      assert is_map(map)
      assert Map.get(map, :US) == :USD
      assert Map.get(map, :AU) == :AUD
      assert Map.get(map, :JP) == :JPY
    end

    test "excludes ZZ territory" do
      map = Currency.current_territory_currencies()
      refute Map.has_key?(map, :ZZ)
    end
  end

  describe "currency_from_locale/1" do
    test "returns currency from territory" do
      {:ok, tag} = Localize.LanguageTag.parse("en-US")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert {:ok, :USD} = Currency.currency_from_locale(tag)
    end

    test "returns currency from cu extension" do
      {:ok, tag} = Localize.LanguageTag.parse("en-US-u-cu-eur")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert {:ok, :EUR} = Currency.currency_from_locale(tag)
    end

    test "accepts a string locale identifier" do
      assert {:ok, :AUD} = Currency.currency_from_locale("en-AU")
    end

    test "accepts an atom locale identifier" do
      assert {:ok, :USD} = Currency.currency_from_locale(:en)
    end
  end

  describe "currency_format_from_locale/1" do
    test "returns :currency by default" do
      {:ok, tag} = Localize.LanguageTag.parse("en-US")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert {:ok, :currency} = Currency.currency_format_from_locale(tag)
    end

    test "returns :accounting for cf-account" do
      {:ok, tag} = Localize.LanguageTag.parse("en-US-u-cf-account")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert {:ok, :accounting} = Currency.currency_format_from_locale(tag)
    end

    test "accepts a string locale identifier" do
      assert {:ok, :currency} = Currency.currency_format_from_locale("en-US")
    end
  end

  describe "current_currency_from_locale/1" do
    test "returns currency for a language tag" do
      {:ok, tag} = Localize.LanguageTag.parse("en-AU")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert {:ok, :AUD} = Currency.current_currency_from_locale(tag)
    end

    test "accepts a string locale identifier" do
      assert {:ok, :USD} = Currency.current_currency_from_locale("en-US")
    end

    test "accepts an atom locale identifier" do
      assert {:ok, _currency} = Currency.current_currency_from_locale(:en)
    end
  end

  describe "struct" do
    test "has expected default values" do
      currency = %Currency{}
      assert currency.code == nil
      assert currency.name == ""
      assert currency.symbol == ""
      assert currency.digits == 0
      assert currency.tender == false
    end
  end

  describe "locale-specific currency functions" do
    test "currency_for_code returns localized currency data" do
      assert {:ok, currency} = Currency.currency_for_code(:USD)
      assert currency.code == :USD
      assert currency.name == "US Dollar"
      assert currency.symbol == "$"
      assert currency.digits == 2
    end

    test "currency_for_code with locale option" do
      assert {:ok, currency} = Currency.currency_for_code(:USD, locale: :en)
      assert currency.name == "US Dollar"
    end

    test "currency_for_code returns error for unknown currency" do
      assert {:error, %Localize.UnknownCurrencyError{}} =
               Currency.currency_for_code(:ZZZ)
    end

    test "currency_for_code returns CurrencyNotLocalizedError for valid currency missing in locale" do
      # VED (Bolívar Soberano) and UYW (Uruguayan Nominal Wage Index Unit) are
      # tender currencies whose CLDR display names exist in :en but not in many
      # other locales. Without :fallback, the request must fail explicitly
      # rather than returning {:ok, nil} or masking as UnknownCurrencyError.
      assert {:error, %Localize.CurrencyNotLocalizedError{currency: :VED, locale: :es}} =
               Currency.currency_for_code(:VED, locale: :es)

      assert {:error, %Localize.CurrencyNotLocalizedError{currency: :UYW, locale: :de}} =
               Currency.currency_for_code(:UYW, locale: :de)
    end

    test "currency_for_code with fallback: true walks the locale chain" do
      assert {:ok, currency} = Currency.currency_for_code(:VED, locale: :es, fallback: true)
      assert currency.code == :VED
      assert is_binary(currency.name)

      assert {:ok, currency} = Currency.currency_for_code(:UYW, locale: :de, fallback: true)
      assert currency.code == :UYW
      assert is_binary(currency.name)
    end

    test "currency_for_code with fallback: true still errors for unknown codes" do
      assert {:error, %Localize.UnknownCurrencyError{}} =
               Currency.currency_for_code(:ZZZ, locale: :es, fallback: true)
    end

    test "currency_for_code with fallback: true uses requested locale when data exists" do
      # When the requested locale already has the currency, fallback must not
      # change the answer.
      assert {:ok, currency} = Currency.currency_for_code(:USD, locale: :fr, fallback: true)
      assert currency.code == :USD
      assert currency.name == "dollar des États-Unis"
    end

    test "currencies_for_locale returns all currencies for a locale" do
      assert {:ok, currencies} = Currency.currencies_for_locale(:en)
      assert is_map(currencies)
      assert Map.has_key?(currencies, :USD)
      assert %Currency{} = currencies[:USD]
    end

    test "currencies_for_locale with string locale" do
      assert {:ok, currencies} = Currency.currencies_for_locale("en")
      assert Map.has_key?(currencies, :USD)
    end

    test "currency_strings returns inverted string map" do
      assert {:ok, strings} = Currency.currency_strings(:en)
      assert is_map(strings)
      assert strings["us dollar"] == :USD || strings["us dollars"] == :USD
    end

    test "display_name returns the currency name" do
      assert {:ok, "US Dollar"} = Currency.display_name(:USD)
    end

    test "display_name with struct" do
      currency = %Currency{name: "Euro", code: :EUR}
      assert {:ok, "Euro"} = Currency.display_name(currency)
    end

    test "display_name with nil name returns error" do
      currency = %Currency{name: nil, code: :XYZ}

      assert {:error, %Localize.CurrencyNoDisplayNameError{}} =
               Currency.display_name(currency)
    end

    test "pluralize returns singular form" do
      assert {:ok, "US dollar"} = Currency.pluralize(1, :USD)
    end

    test "pluralize returns plural form" do
      assert {:ok, "US dollars"} = Currency.pluralize(3, :USD)
    end
  end

  describe "currency_filter/3" do
    test "filtering by :current excludes historic currencies" do
      {:ok, current} = Currency.currencies_for_locale(:en, :current)
      refute Map.has_key?(current, :SDP)
      assert Map.has_key?(current, :USD)
    end

    test "filtering by :historic includes historic currencies" do
      {:ok, historic} = Currency.currencies_for_locale(:en, :historic)
      assert Map.has_key?(historic, :SDP)
      assert Map.has_key?(historic, :ZWR)
    end

    test "filtering by :tender includes only tender currencies" do
      {:ok, tender} = Currency.currencies_for_locale(:en, :tender)

      Enum.each(tender, fn {_code, currency} ->
        assert Currency.tender?(currency)
      end)
    end

    test "filtering by :unannotated excludes annotated currencies" do
      {:ok, unannotated} = Currency.currencies_for_locale(:en, :unannotated)

      Enum.each(unannotated, fn {_code, currency} ->
        refute String.contains?(currency.name, "(")
      end)
    end

    test "filtering with :all returns all currencies" do
      {:ok, all} = Currency.currencies_for_locale(:en, :all)
      assert map_size(all) > 200
    end

    test "filtering with except removes currencies" do
      {:ok, all} = Currency.currencies_for_locale(:en)
      {:ok, no_historic} = Currency.currencies_for_locale(:en, :all, :historic)
      assert map_size(no_historic) < map_size(all)
    end
  end

  describe "currency predicates" do
    test "current?/1 returns true for active currencies" do
      {:ok, currencies} = Currency.currencies_for_locale(:en)
      assert Currency.current?(currencies[:USD])
      assert Currency.current?(currencies[:EUR])
    end

    test "historic?/1 returns true for currencies with nil iso_digits" do
      {:ok, currencies} = Currency.currencies_for_locale(:en)
      assert Currency.historic?(currencies[:SDP])
      assert Currency.historic?(currencies[:ZWR])
    end

    test "historic?/1 returns false for active currencies" do
      {:ok, currencies} = Currency.currencies_for_locale(:en)
      refute Currency.historic?(currencies[:USD])
    end

    test "tender?/1 returns true for legal tender" do
      {:ok, currencies} = Currency.currencies_for_locale(:en)
      assert Currency.tender?(currencies[:USD])
    end

    test "annotated?/1 returns true for currencies with annotations" do
      {:ok, currencies} = Currency.currencies_for_locale(:en)
      # USN has "(Next day)" annotation
      assert Currency.annotated?(currencies[:USN])
    end

    test "unannotated?/1 returns true for currencies without annotations" do
      {:ok, currencies} = Currency.currencies_for_locale(:en)
      assert Currency.unannotated?(currencies[:USD])
    end
  end

  describe "currency_strings edge cases" do
    test "dollar sign maps to USD in en locale" do
      {:ok, strings} = Currency.currency_strings(:en)
      assert strings["$"] == :USD
    end

    test "narrow symbol R maps to ZAR in en locale" do
      {:ok, strings} = Currency.currency_strings(:en)
      assert strings["r"] == :ZAR
    end

    test "annotated currency names are preserved" do
      {:ok, currencies} = Currency.currencies_for_locale(:en)
      usn = currencies[:USN]
      assert usn.name =~ "(Next day)"
    end

    test "RTL markers are stripped from currency strings" do
      {:ok, strings} = Currency.currency_strings(:ar)
      # No string should end with the RTL mark
      rtl_mark = "\u200F"

      Enum.each(strings, fn {string, _code} ->
        refute String.ends_with?(string, rtl_mark),
               "String #{inspect(string)} should not end with RTL mark"
      end)
    end

    test "currency strings work with non-Latin locales" do
      {:ok, strings} = Currency.currency_strings(:ar)
      assert is_map(strings)
      assert map_size(strings) > 0
      assert Map.has_key?(strings, "mad")
    end
  end

  describe "strings_for_currency/2" do
    test "returns all string variants for a currency" do
      {:ok, strings} = Currency.strings_for_currency(:AUD, :en)
      assert is_list(strings)
      assert "aud" in strings
      assert "australian dollar" in strings || "australian dollars" in strings
    end

    test "returns strings for a string currency code" do
      {:ok, strings} = Currency.strings_for_currency("USD", :en)
      assert "usd" in strings
      assert "us dollar" in strings
    end

    test "includes symbol strings" do
      {:ok, strings} = Currency.strings_for_currency(:AUD, :en)
      assert "a$" in strings
    end

    test "returns error for unknown currency" do
      assert {:error, %Localize.UnknownCurrencyError{}} =
               Currency.strings_for_currency(:ZZZ, :en)
    end
  end

  describe "bang versions" do
    test "currency_for_code! returns currency struct" do
      currency = Currency.currency_for_code!(:USD)
      assert %Currency{} = currency
      assert currency.code == :USD
      assert currency.name == "US Dollar"
    end

    test "currency_for_code! raises for unknown currency" do
      assert_raise Localize.UnknownCurrencyError, fn ->
        Currency.currency_for_code!(:ZZZ)
      end
    end

    test "currencies_for_locale! returns currencies map" do
      currencies = Currency.currencies_for_locale!(:en)
      assert is_map(currencies)
      assert Map.has_key?(currencies, :USD)
    end

    test "currencies_for_locale! with filter" do
      current = Currency.currencies_for_locale!(:en, :current)
      assert Map.has_key?(current, :USD)
      refute Map.has_key?(current, :SDP)
    end

    test "currency_strings! returns string map" do
      strings = Currency.currency_strings!(:en)
      assert is_map(strings)
      assert strings["us dollar"] == :USD
    end

    test "display_name! returns name string" do
      assert "US Dollar" = Currency.display_name!(:USD)
    end

    test "display_name! raises for currency with no name" do
      currency = %Currency{name: nil, code: :XYZ}

      assert_raise Localize.CurrencyNoDisplayNameError, fn ->
        Currency.display_name!(currency)
      end
    end
  end

  describe "current_currency_for_territory edge cases" do
    test "Antarctica has no current currency" do
      assert is_nil(Currency.current_currency_for_territory(:AQ))
    end
  end

  # Regression: each of these public entry points used to call
  # `String.to_atom/1` on the binary input BEFORE checking membership
  # in the validity set, so an attacker could grow the atom table
  # unboundedly. Atomisation is now gated on `Helpers.existing_atom/1`.
  #
  # We verify by feeding a unique bogus string into each entry point
  # and asserting the atom doesn't exist after the call — checking
  # `:erlang.system_info(:atom_count)` would race with concurrent
  # async tests creating unrelated atoms.
  describe "atom-table bound on unknown binary input" do
    test "validate_currency does not create an atom for unknown code" do
      bogus = "ZZZ_validate_currency_#{System.unique_integer([:positive])}"
      assert {:error, _} = Currency.validate_currency(bogus)
      assert {:error, _} = Currency.validate_currency(String.downcase(bogus))
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(String.upcase(bogus))
    end

    test "territory_currencies does not create an atom for unknown territory" do
      bogus = "ZZZ_territory_#{System.unique_integer([:positive])}"
      assert {:error, _} = Currency.territory_currencies(bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(String.upcase(bogus))
    end

    test "current_currency_for_territory does not create an atom for unknown territory" do
      bogus = "ZZZ_current_#{System.unique_integer([:positive])}"
      assert is_nil(Currency.current_currency_for_territory(bogus))
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(String.upcase(bogus))
    end

    test "currencies_for_locale filter does not create an atom for unknown code" do
      bogus = "ZZZ_filter_#{System.unique_integer([:positive])}"
      # `only` accepts a list of filter terms including bare currency
      # codes. Unknown binary codes must filter to no rows without
      # atomising.
      assert {:ok, result} = Currency.currencies_for_locale(:en, [bogus])
      assert result == %{}
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end
  end
end
