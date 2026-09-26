defmodule Localize.CurrencyStringsCacheTest do
  # async: false because the tests clear the global cache and
  # replace stored locale data.
  use ExUnit.Case, async: false

  alias Localize.Currency

  test "a cached call returns the same map as an uncached call for en, de-CH, fr-CH and ar" do
    for locale <- [:en, :"de-CH", :"fr-CH", :ar], options <- [[], [only: :current]] do
      {:ok, cached} = Currency.currency_strings(locale, options)
      assert {:ok, ^cached} = Currency.currency_strings(locale, options)

      :ok = Localize.FormatCache.clear()
      assert {:ok, ^cached} = Currency.currency_strings(locale, options)
    end
  end

  test "an :only filter after an unfiltered call in en resolves \"kr\" to NOK" do
    {:ok, all} = Currency.currency_strings(:en)
    refute Map.has_key?(all, "kr")

    assert {:ok, %{"kr" => :NOK}} = Currency.currency_strings(:en, only: [:NOK])
  end

  test "storing de-CH data with a renamed Swiss franc changes the de-CH currency strings" do
    {:ok, original} = Localize.Locale.load(:"de-CH")
    on_exit(fn -> Localize.Locale.store(:"de-CH", original) end)

    assert {:ok, %{"schweizer franken" => :CHF}} = Currency.currency_strings(:"de-CH")

    renamed = update_in(original, [:currencies, :CHF], &%{&1 | name: "Franken Test"})
    :ok = Localize.Locale.store(:"de-CH", renamed)

    assert {:ok, %{"franken test" => :CHF}} = Currency.currency_strings(:"de-CH")
  end
end
