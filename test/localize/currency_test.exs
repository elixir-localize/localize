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
      assert :USD = Currency.currency_from_locale(tag)
    end

    test "returns currency from cu extension" do
      {:ok, tag} = Localize.LanguageTag.parse("en-US-u-cu-eur")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert :EUR = Currency.currency_from_locale(tag)
    end
  end

  describe "currency_format_from_locale/1" do
    test "returns :currency by default" do
      {:ok, tag} = Localize.LanguageTag.parse("en-US")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert :currency = Currency.currency_format_from_locale(tag)
    end

    test "returns :accounting for cf-account" do
      {:ok, tag} = Localize.LanguageTag.parse("en-US-u-cf-account")
      {:ok, tag} = Localize.LanguageTag.canonicalize(tag)
      assert :accounting = Currency.currency_format_from_locale(tag)
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

  describe "stub functions" do
    test "currency_for_code returns not_yet_implemented" do
      assert {:error, :not_yet_implemented} = Currency.currency_for_code(:USD)
    end

    test "currencies_for_locale returns not_yet_implemented" do
      assert {:error, :not_yet_implemented} = Currency.currencies_for_locale("en")
    end

    test "currency_strings returns not_yet_implemented" do
      assert {:error, :not_yet_implemented} = Currency.currency_strings("en")
    end

    test "display_name returns not_yet_implemented" do
      assert {:error, :not_yet_implemented} = Currency.display_name(:USD)
    end

    test "pluralize returns not_yet_implemented" do
      assert {:error, :not_yet_implemented} = Currency.pluralize(1, :USD)
    end
  end
end
