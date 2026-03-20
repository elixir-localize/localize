defmodule Localize.Currency.StoreTest do
  use ExUnit.Case, async: false

  alias Localize.Currency
  alias Localize.Currency.Store

  describe "custom currency lifecycle" do
    test "new/2 creates and stores a custom currency" do
      assert {:ok, currency} =
               Currency.new(:QFFP, name: "QANTAS Frequent Flyer Points", digits: 0)

      assert currency.code == :QFFP
      assert currency.name == "QANTAS Frequent Flyer Points"
      assert currency.digits == 0
      assert currency.tender == false
      assert currency.symbol == "QFFP"
      assert currency.count == %{other: "QANTAS Frequent Flyer Points"}
    end

    test "custom currency is available via Store.get/1" do
      {:ok, _} = Currency.new(:XTEST, name: "Test Currency", digits: 2)
      currency = Store.get(:XTEST)
      assert currency.code == :XTEST
      assert currency.name == "Test Currency"
    end

    test "custom currency appears in known_currency_codes" do
      {:ok, _} = Currency.new(:XKNOWN, name: "Known Test", digits: 0)
      assert :XKNOWN in Currency.known_currency_codes()
    end

    test "custom currency appears in private_currency_codes" do
      {:ok, _} = Currency.new(:XPRIV, name: "Private Test", digits: 0)
      assert :XPRIV in Currency.private_currency_codes()
    end

    test "custom currency validates" do
      {:ok, _} = Currency.new(:XVALID, name: "Valid Test", digits: 0)
      assert {:ok, :XVALID} = Currency.validate_currency(:XVALID)
    end

    test "cannot create currency with existing ISO code" do
      assert {:error, %Localize.CurrencyAlreadyDefinedError{}} =
               Currency.new(:USD, name: "US Dollar", digits: 2)
    end

    test "requires name and digits options" do
      assert {:error, %Localize.InvalidValueError{}} =
               Currency.new(:XMISS, name: "Missing Digits")

      assert {:error, %Localize.InvalidValueError{}} =
               Currency.new(:XMISS, digits: 2)
    end

    test "rejects invalid currency codes" do
      assert {:error, %Localize.UnknownCurrencyError{}} =
               Currency.new(:AB, name: "Too Short", digits: 0)
    end

    test "Store.all/0 returns all custom currencies" do
      {:ok, _} = Currency.new(:XALL1, name: "All Test 1", digits: 0)
      currencies = Store.all()
      assert is_map(currencies)
      assert Map.has_key?(currencies, :XALL1)
    end
  end
end
